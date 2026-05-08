// darksheets.user.js
// ==UserScript==
// @name        Google Sheets: invert waffle grid
// @match       https://docs.google.com/spreadsheets/*
// @run-at      document-end
// @grant       none
// ==/UserScript==

(() => {
  const FILTER = "invert(1) hue-rotate(180deg) contrast(0.92) saturate(0.85)";
  const TARGETS = ["#waffle-grid-container", ".waffle-grid-container"];
  const THEME = {
    bg: "#101825",
    fg: "#d9e6fa",
  };

  const apply = (doc) => {
    for (const sel of TARGETS) {
      const el = doc.querySelector(sel);
      if (el) {
        el.style.filter = FILTER;
        el.style.background = THEME.bg;
        return true;
      }
    }
    return false;
  };

  const docs = [document];
  for (const f of document.querySelectorAll("iframe")) {
    try {
      if (f.contentDocument) docs.push(f.contentDocument);
    } catch {}
  }

  const tick = () => docs.some(apply);

  tick();
  new MutationObserver(tick).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
})();
