// darkgoogledocs.user.js
// ==UserScript==
// @name        Google Docs: invert editor + force dark surround
// @match       https://docs.google.com/document/*
// @run-at      document-end
// @grant       none
// ==/UserScript==

(() => {
  // const FILTER = "invert(1) hue-rotate(180deg) contrast(0.92) saturate(0.85)";
  const FILTER =
    "invert(0.95) hue-rotate(180deg) brightness(0.92) contrast(0.95) saturate(0.90)";
  const BG = "#101825";

  const ensureStyle = (doc) => {
    const id = "__docs_dark_surround__";
    if (doc.getElementById(id)) return;

    const s = doc.createElement("style");
    s.id = id;

    // Force dark background on editor + surrounding containers.
    // Includes pseudo-elements because Docs sometimes paints white via ::before/::after.
    s.textContent = `
      html, body { background: ${BG} !important; }

      .kix-appview,
      .kix-appview-editor-container,
      .kix-appview-editor {
        background: ${BG} !important;
        background-color: ${BG} !important;
      }

      .kix-appview-editor::before,
      .kix-appview-editor::after,
      .kix-appview-editor-container::before,
      .kix-appview-editor-container::after {
        background: ${BG} !important;
        background-color: ${BG} !important;
      }
    `;
    (doc.head || doc.documentElement).appendChild(s);
  };

  const apply = (doc) => {
    if (!doc) return false;
    ensureStyle(doc);

    const els = doc.querySelectorAll(
      ".kix-rotatingtilemanager .kix-page-paginated",
    );
    if (!els.length) return false;

    for (const el of els) {
      el.style.filter = FILTER;
      el.style.background = "#000";
    }
    return true;
  };

  const frameDocs = (rootDoc) => {
    const out = [];
    for (const f of rootDoc.querySelectorAll("iframe")) {
      try {
        if (f.contentDocument) out.push(f.contentDocument);
      } catch {}
    }
    return out;
  };

  const tick = () => {
    if (apply(document)) return true;
    for (const d of frameDocs(document)) {
      if (apply(d)) return true;
      for (const dd of frameDocs(d)) {
        if (apply(dd)) return true;
      }
    }
    return false;
  };

  tick();
  new MutationObserver(tick).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });

  // Docs builds UI progressively; retry briefly
  let n = 0;
  const iv = setInterval(() => {
    tick();
    if (++n >= 40) clearInterval(iv);
  }, 500);
})();
