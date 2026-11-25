/// JavaScript injected into every Instagram page before it loads.
/// Edit the settings at the top of the script to change what gets hidden.
enum FilterScript {
    static let source = #"""
(function () {
  'use strict';

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

  // ---- Styles -------------------------------------------------------------
  const css = `
    a[href="/reels/"], a[href^="/reels/?"] { display: none !important; }
    ${HIDE_FEED_REELS ? 'html.nr-home article:has(a[href*="/reel/"]) { display: none !important; }' : ''}
    ${BLOCK_EXPLORE ? 'a[href="/explore/"] { display: none !important; }' : ''}
  `;
  function injectStyle() {
    if (document.getElementById('nr-style')) return;
    const style = document.createElement('style');
    style.id = 'nr-style';
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  }

  // ---- "Open in app" banners ---------------------------------------------
  const APP_LINK = /apps\.apple\.com|itunes\.apple\.com|instagram:\/\/|app\.link|\/download\/?$/i;
  const APP_TEXT = /^(open|use|get|switch to)( the| in)?( instagram)?( app)?$|^open instagram$/i;
  const NAV_LINKS = 'a[href^="/direct"], a[href="/explore/"], a[href="/accounts/activity/"], nav';

  function hideAppBanner() {
    document.querySelectorAll('a, button, [role="button"]').forEach((el) => {
      if (el.dataset.nrChecked) return;
      el.dataset.nrChecked = '1';
      const text = (el.textContent || '').trim();
      const href = el.getAttribute('href') || '';
      if (!APP_LINK.test(href) && !(text.length < 30 && APP_TEXT.test(text))) return;
      let box = el;
      while (box.parentElement && box.parentElement !== document.body) {
        const p = box.parentElement;
        if (p.offsetHeight > 100 || p.querySelector(NAV_LINKS)) break;
        box = p;
      }
      box.style.setProperty('display', 'none', 'important');
    });
  }

  // ---- Navigation guard ---------------------------------------------------
  function check() {
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
    const root = document.documentElement;
    root.classList.toggle('nr-reel', onReel);
    root.classList.toggle('nr-home', path === '/');
  }

  // ---- Block swiping while a reel is open --------------------------------
  function allowedTarget(el) {
    return el && el.closest && el.closest('textarea, input, [contenteditable="true"], [role="dialog"] ul');
  }

  let startX = 0, startY = 0;
  window.addEventListener('touchstart', (e) => {
    const t = e.touches[0];
    if (t) { startX = t.clientX; startY = t.clientY; }
  }, { capture: true, passive: true });

  window.addEventListener('touchmove', (e) => {
    if (!onReel || allowedTarget(e.target)) return;
    const t = e.touches[0];
    if (!t) return;
    if (Math.abs(t.clientY - startY) > Math.abs(t.clientX - startX)) e.preventDefault();
  }, { capture: true, passive: false });

  // ---- Start --------------------------------------------------------------
  check();
  window.addEventListener('popstate', check);
  setInterval(check, 250);
  if (HIDE_APP_BANNER) setInterval(hideAppBanner, 700);
})();
"""#
}
