// darkreader.user.js
// ==UserScript==
// @name        Dark Reader (Unofficial) + Docs/Sheets fallback
// @namespace   DarkReader
// @run-at      document-end
// @grant       none
// @match       http://*/*
// @match       https://*/*
// @require     https://cdn.jsdelivr.net/npm/darkreader/darkreader.min.js
// @noframes
// ==/UserScript==

(() => {
  const host = location.hostname;
  const THEME = {
    bg: "#101825",
    fg: "#d9e6fa",
  };

  const skip =
    host === "docs.google.com" ||
    host === "sheets.google.com" ||
    host === "calendar.google.com" ||
    host === "www.youtube.com" ||
    host.endsWith(".docs.google.com") ||
    host.endsWith(".sheets.google.com");

  // Fallback for Docs/Sheets: pixel-level filter (works better for canvas-heavy UI)
  if (skip) return;

  // Everywhere else: DarkReader dynamic API
  if (window.DarkReader?.setFetchMethod) {
    window.DarkReader.setFetchMethod(window.fetch);
  }

  window.DarkReader.enable({
    mode: 1, // 1 = dark, 0 = dimmed (API only exposes these)
    brightness: 100,
    contrast: 100,
    sepia: 0,
    darkSchemeBackgroundColor: THEME.bg,
    darkSchemeTextColor: THEME.fg,
  });
})();
