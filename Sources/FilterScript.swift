/// JavaScript injected into every Instagram page before it loads.
/// Edit the settings at the top of the script to change what gets hidden.
///
/// Rules this script follows:
/// - Hide things with data-* attributes, never class names (Instagram's React redraws reset classes).
/// - No non-passive touch/scroll listeners (they make every scroll wait for JS).
/// - Only re-check the page in small batches after it changes, never scan it constantly.
enum FilterScript {
    static let source = #"""
(function () {
  'use strict';
  if (window.__focusFeed) return;
  window.__focusFeed = true;

  // ---- Settings -----------------------------------------------------------
  const BLOCK_EXPLORE = false;      // true = also block the Explore page
  const HIDE_FEED_REELS = true;     // true = hide reels mixed into the home feed
  const HIDE_APP_BANNER = true;     // true = hide "Open in app" / "Use the app" prompts
  // -------------------------------------------------------------------------

  const native = (msg) => {
    try { window.webkit.messageHandlers.ff.postMessage(msg); } catch (e) {}
  };

  // ---- Styles -------------------------------------------------------------
  const css = `
    html { -webkit-tap-highlight-color: transparent; touch-action: manipulation; }
    a, img, svg, video, [role="button"], button {
      -webkit-touch-callout: none; -webkit-user-select: none; user-select: none;
    }
    a[href="/reels/"], a[href^="/reels/?"] { display: none !important; }
    [data-ff-hide] { display: none !important; }
    [data-ff-locked] { overflow: hidden !important; overscroll-behavior: none !important; }
    ${BLOCK_EXPLORE ? 'a[href="/explore/"] { display: none !important; }' : ''}
  `;
  function injectStyle() {
    if (document.getElementById('ff-style')) return;
    const style = document.createElement('style');
    style.id = 'ff-style';
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  }

  // No pinch / double-tap zoom, like the app.
  function fixViewport() {
    const head = document.head;
    if (!head) return;
    let meta = head.querySelector('meta[name="viewport"]');
    if (!meta) { meta = document.createElement('meta'); meta.name = 'viewport'; head.appendChild(meta); }
    const want = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=auto';
    if (meta.content !== want) meta.content = want;
  }

  // ---- Navigation guard ---------------------------------------------------
  const REELS_TAB = /^\/reels\/?$/;    // the endless Reels feed
  let lastPath = null;

  function onNavigate() {
    injectStyle();
    const path = location.pathname;
    if (path === lastPath) return;
    lastPath = path;
    if (REELS_TAB.test(path) || (BLOCK_EXPLORE && path.startsWith('/explore'))) {
      location.replace('/');
      return;
    }
    scheduleScan();
  }

  ['pushState', 'replaceState'].forEach((fn) => {
    const orig = history[fn];
    history[fn] = function () {
      const result = orig.apply(this, arguments);
      setTimeout(onNavigate, 0);
      return result;
    };
  });
  window.addEventListener('popstate', onNavigate);

  // ---- Reel viewer: keep only the reel you opened ---------------------------
  // Tapping a reel in a DM opens a full-screen, snap-scrolling list (no address change) that
  // also holds the chat's other reels and "Suggested" reels. Everything except the reel you
  // opened is hidden, so there is physically nothing to scroll to.
  const vh = () => window.innerHeight || document.documentElement.clientHeight;

  function isVerticalSnapScroller(n) {
    const t = getComputedStyle(n).scrollSnapType;
    return !!t && t !== 'none' && !/^(x|inline)\b/.test(t);
  }

  function mostVisibleBigVideo(root) {
    const h = vh();
    let best = null, bestVisible = 0;
    for (const v of root.getElementsByTagName('video')) {
      const r = v.getBoundingClientRect();
      if (r.height < h * 0.75) continue;
      const visible = Math.min(r.bottom, h) - Math.max(r.top, 0);
      if (visible > bestVisible) { bestVisible = visible; best = v; }
    }
    return best;
  }

  function reelItemFor(video, scroller) {
    let item = video;
    while (item.parentElement && item.parentElement !== scroller &&
           getComputedStyle(item).scrollSnapAlign === 'none') item = item.parentElement;
    return item;
  }

  let viewer = null;       // the snap-scrolling list
  let keep = null;         // the one reel left visible
  let candidate = null;    // reel waiting to be confirmed (Instagram scrolls to it after opening)
  let candidateAt = 0;

  function releaseViewer() {
    if (viewer) {
      viewer.removeAttribute('data-ff-locked');
      viewer.querySelectorAll('[data-ff-hide]').forEach((n) => n.removeAttribute('data-ff-hide'));
    }
    viewer = keep = null;
  }

  function lockViewer() {
    if (viewer) {
      const stillOpen = viewer.isConnected && keep && keep.isConnected && keep.getBoundingClientRect().height > 0;
      if (!stillOpen) releaseViewer();
    }

    if (!viewer) {
      const video = mostVisibleBigVideo(document);
      if (!video) { candidate = null; return; }
      let sc = video.parentElement;
      while (sc && sc !== document.body && !isVerticalSnapScroller(sc)) sc = sc.parentElement;
      if (!sc || sc === document.body) { candidate = null; return; }
      const item = reelItemFor(video, sc);

      // Wait until the same reel is still the one on screen a moment later.
      const now = Date.now();
      if (candidate !== item) {
        candidate = item; candidateAt = now;
        setTimeout(scheduleScan, 260);
        return;
      }
      if (now - candidateAt < 250) { setTimeout(scheduleScan, 260); return; }
      viewer = sc; keep = item; candidate = null;
    }

    for (let a = keep; a && a !== viewer && a.parentElement; a = a.parentElement) {
      for (const sib of a.parentElement.children) {
        if (sib !== a && !sib.hasAttribute('data-ff-hide')) sib.setAttribute('data-ff-hide', '');
      }
    }
    if (!viewer.hasAttribute('data-ff-locked')) viewer.setAttribute('data-ff-locked', '');
  }

  // ---- Feed reels ---------------------------------------------------------
  // Reels in the feed link to /reels/<id>/, /<user>/reel/<id>/ or /reels/audio/<id>/.
  function hideFeedReels() {
    if (location.pathname !== '/') return;
    document.querySelectorAll('article a[href*="/reel/"], article a[href^="/reels/"]').forEach((a) => {
      const art = a.closest('article');
      if (art && !art.hasAttribute('data-ff-hide')) art.setAttribute('data-ff-hide', '');
    });
  }

  // ---- "Open in app" banners (new elements only) --------------------------
  const APP_LINK = /apps\.apple\.com|itunes\.apple\.com|instagram:\/\/|app\.link|\/download\/?$/i;
  const APP_TEXT = /^(open|use|get|switch to)( the| in)?( instagram)?( app)?$|^open instagram$/i;
  const NAV_LINKS = 'a[href^="/direct"], a[href="/explore/"], a[href="/notifications/"], nav';

  function hideBannerButton(el) {
    const text = (el.textContent || '').trim();
    const href = el.getAttribute('href') || '';
    if (!APP_LINK.test(href) && !(text.length < 30 && APP_TEXT.test(text))) return;
    let box = el;
    while (box.parentElement && box.parentElement !== document.body) {
      const p = box.parentElement;
      if (p.offsetHeight > 100 || p.querySelector(NAV_LINKS)) break;
      box = p;
    }
    box.setAttribute('data-ff-hide', '');
  }

  function hideBanners(root) {
    if (root.matches && root.matches('a, button, [role="button"]')) hideBannerButton(root);
    if (root.querySelectorAll) root.querySelectorAll('a, button, [role="button"]').forEach(hideBannerButton);
  }

  // ---- Bottom bar: haptics, and Home at the top of the feed = refresh -------
  function bottomBarLink(target) {
    const a = target && target.closest && target.closest('a[href]');
    if (!a) return null;
    const r = a.getBoundingClientRect();
    return r.top > vh() - 90 ? a : null;
  }

  window.addEventListener('click', (e) => {
    const a = bottomBarLink(e.target);
    if (!a) return;
    const href = a.getAttribute('href');
    const scroller = document.scrollingElement || document.documentElement;
    if (href === '/' && location.pathname === '/' && scroller.scrollTop < 8) {
      e.preventDefault();
      e.stopImmediatePropagation();
      native({ type: 'refresh' });           // already at the top: refresh, like the app
      return;
    }
    native({ type: 'haptic', style: 'light' });
  }, true);

  // ---- Page background colour -> native safe areas ------------------------
  let lastBg = '';
  function reportBackground() {
    if (!document.body) return;
    const bg = getComputedStyle(document.body).backgroundColor;
    if (bg && bg !== lastBg && bg !== 'rgba(0, 0, 0, 0)') { lastBg = bg; native({ type: 'background', color: bg }); }
  }

  // ---- Batched scanning ---------------------------------------------------
  let pending = [];
  let timer = 0;

  function scheduleScan() {
    if (!timer) timer = setTimeout(runScan, 120);
  }

  function runScan() {
    timer = 0;
    injectStyle();
    fixViewport();
    const nodes = pending;
    pending = [];
    if (HIDE_APP_BANNER) {
      for (const n of nodes) if (n.nodeType === 1 && n.isConnected) hideBanners(n);
    }
    if (HIDE_FEED_REELS) hideFeedReels();
    lockViewer();
    reportBackground();
  }

  new MutationObserver((records) => {
    for (const r of records) for (const n of r.addedNodes) if (n.nodeType === 1) pending.push(n);
    if (pending.length) scheduleScan();
  }).observe(document.documentElement, { childList: true, subtree: true });

  // Videos can grow/move without DOM changes; light re-check once a second.
  setInterval(() => { onNavigate(); lockViewer(); reportBackground(); }, 1000);

  onNavigate();
})();
"""#
}
