/// JavaScript injected into every Instagram page before it loads.
/// Edit the settings at the top of the script to change what gets hidden.
///
/// Performance rules this script follows:
/// - No non-passive touch/scroll listeners on the page (those make every scroll wait for JS).
/// - No polling of the whole page: only newly added elements are checked, in batches.
/// - No expensive CSS selectors such as :has().
enum FilterScript {
    static let source = #"""
(function () {
  'use strict';
  if (window.__focusFeed) return;
  window.__focusFeed = true;

  // ---- Settings -----------------------------------------------------------
  const BLOCK_EXPLORE = false;      // true = also block the Explore page (mostly reels)
  const HIDE_FEED_REELS = true;     // true = hide reels mixed into the home feed
  const HIDE_APP_BANNER = true;     // true = hide "Open in app" / "Use the app" prompts
  // -------------------------------------------------------------------------

  const REEL_PATH = /^\/reels?\/([A-Za-z0-9_-]+)/;   // /reel/<id> or /reels/<id>
  const REELS_TAB = /^\/reels\/?$/;                  // the endless Reels feed

  let lastPath = null;
  let allowedReel = null;
  let onReel = false;

  // ---- Styles (cheap selectors only) --------------------------------------
  const css = `
    a[href="/reels/"], a[href^="/reels/?"] { display: none !important; }
    .ff-hidden { display: none !important; }
    .ff-locked { overflow: hidden !important; overscroll-behavior: none !important;
                 touch-action: pan-x pinch-zoom !important; }
    ${BLOCK_EXPLORE ? 'a[href="/explore/"] { display: none !important; }' : ''}
  `;
  function injectStyle() {
    if (document.getElementById('ff-style')) return;
    const style = document.createElement('style');
    style.id = 'ff-style';
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  }

  // ---- Navigation guard ---------------------------------------------------
  function onNavigate() {
    injectStyle();
    const path = location.pathname;
    if (path === lastPath) return;
    const prev = lastPath;
    lastPath = path;

    if (REELS_TAB.test(path) || (BLOCK_EXPLORE && path.startsWith('/explore'))) {
      location.replace('/');
      return;
    }

    const m = path.match(REEL_PATH);
    if (m) {
      const id = m[1];
      const cameFromReel = prev !== null && REEL_PATH.test(prev);
      if (!cameFromReel || !allowedReel) {
        allowedReel = id;                                   // opened from a DM, profile, etc.
      } else if (id !== allowedReel) {
        location.replace('/reel/' + allowedReel + '/');     // swiped to the next reel
        return;
      }
    } else {
      allowedReel = null;
    }
    onReel = !!m;

    if (HIDE_FEED_REELS && path === '/') hideFeedReels(document);
    scheduleScan();
  }

  // React to Instagram's in-app navigation immediately instead of polling fast.
  ['pushState', 'replaceState'].forEach((fn) => {
    const orig = history[fn];
    history[fn] = function () {
      const result = orig.apply(this, arguments);
      setTimeout(onNavigate, 0);
      return result;
    };
  });
  window.addEventListener('popstate', onNavigate);

  // ---- Feed reels and "open in app" banners (new elements only) -----------
  function hideFeedReels(root) {
    if (location.pathname !== '/') return;          // never on the page of a reel sent to you
    const links = root.querySelectorAll ? root.querySelectorAll('a[href*="/reel/"]') : [];
    for (const a of links) {
      const art = a.closest('article');
      if (art) art.classList.add('ff-hidden');
    }
    if (root.matches && root.matches('a[href*="/reel/"]')) {
      const art = root.closest('article');
      if (art) art.classList.add('ff-hidden');
    }
  }

  const APP_LINK = /apps\.apple\.com|itunes\.apple\.com|instagram:\/\/|app\.link|\/download\/?$/i;
  const APP_TEXT = /^(open|use|get|switch to)( the| in)?( instagram)?( app)?$|^open instagram$/i;
  const NAV_LINKS = 'a[href^="/direct"], a[href="/explore/"], a[href="/accounts/activity/"], nav';

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
    box.classList.add('ff-hidden');
  }

  function hideBanners(root) {
    if (root.matches && root.matches('a, button, [role="button"]')) hideBannerButton(root);
    if (root.querySelectorAll) root.querySelectorAll('a, button, [role="button"]').forEach(hideBannerButton);
  }

  // ---- Reel viewer lock ---------------------------------------------------
  // When a full-screen video is on screen, the area that would scroll to the next reel is
  // locked with CSS (no JS in the scroll path), so swiping does nothing.
  const vh = () => window.innerHeight || document.documentElement.clientHeight;
  const docScroller = () => document.scrollingElement || document.documentElement;

  function scrollParent(el) {
    for (let n = el.parentElement; n && n !== document.body && n !== document.documentElement; n = n.parentElement) {
      const oy = getComputedStyle(n).overflowY;
      if ((oy === 'auto' || oy === 'scroll') && n.scrollHeight > n.clientHeight + 1) return n;
    }
    return docScroller();
  }

  function findReelScroller() {
    const h = vh();
    for (const v of document.getElementsByTagName('video')) {
      const r = v.getBoundingClientRect();
      if (r.height >= h * 0.75 && r.bottom > 0 && r.top < h) return scrollParent(v);
    }
    return onReel ? docScroller() : null;
  }

  let locked = null;
  let lockPos = 0;

  function lockTargets(el) {
    return el === docScroller() ? [document.documentElement, document.body] : [el];
  }

  function setLock(el) {
    if (el === locked) return;
    if (locked) lockTargets(locked).forEach((t) => t && t.classList.remove('ff-locked'));
    locked = el;
    if (el) {
      lockPos = el.scrollTop;
      lockTargets(el).forEach((t) => t && t.classList.add('ff-locked'));
    }
  }

  // Momentum or code that still moves a locked viewer gets put back (passive, cheap).
  document.addEventListener('scroll', (e) => {
    if (!locked) return;
    const el = e.target === document ? docScroller() : e.target;
    if (el === locked && Math.abs(el.scrollTop - lockPos) > 2) el.scrollTop = lockPos;
  }, { capture: true, passive: true });

  // Stop Instagram's own JS swipe handling while locked (passive: never delays scrolling).
  let gesture = null;
  window.addEventListener('touchstart', (e) => {
    if (!locked) { gesture = null; return; }
    const t = e.touches[0];
    const inLocked = locked === docScroller() || locked.contains(e.target);
    gesture = t && inLocked ? { x: t.clientX, y: t.clientY, vertical: false } : null;
  }, { capture: true, passive: true });

  ['touchmove', 'touchend', 'pointermove', 'pointerup'].forEach((type) => {
    window.addEventListener(type, (e) => {
      if (!gesture) return;
      if (type === 'touchmove' && e.touches[0]) {
        const t = e.touches[0];
        if (Math.abs(t.clientY - gesture.y) > Math.abs(t.clientX - gesture.x) + 4) gesture.vertical = true;
      }
      if (gesture.vertical) e.stopImmediatePropagation();
    }, { capture: true, passive: true });
  });

  // ---- Batched scanning of new elements -----------------------------------
  let pending = [];
  let timer = 0;

  function scheduleScan() {
    if (!timer) timer = setTimeout(runScan, 150);
  }

  function runScan() {
    timer = 0;
    injectStyle();
    const nodes = pending;
    pending = [];
    for (const n of nodes) {
      if (n.nodeType !== 1 || !n.isConnected) continue;
      if (HIDE_FEED_REELS) hideFeedReels(n);
      if (HIDE_APP_BANNER) hideBanners(n);
    }
    setLock(findReelScroller());
  }

  new MutationObserver((records) => {
    for (const r of records) {
      for (const n of r.addedNodes) if (n.nodeType === 1) pending.push(n);
    }
    if (pending.length) scheduleScan();
  }).observe(document.documentElement, { childList: true, subtree: true });

  // Videos change size/position without DOM changes; re-check the lock occasionally.
  setInterval(() => { onNavigate(); setLock(findReelScroller()); }, 1000);

  onNavigate();
})();
"""#
}
