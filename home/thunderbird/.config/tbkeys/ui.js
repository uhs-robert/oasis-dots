// Persistent mode/count/status indicator in the mail window's status bar.
(function (tk) {
  "use strict";

  /**
   * @returns {Element} the injected mode/count indicator, or null where the mail status bar is absent (e.g. compose windows)
   */
  tk.ensure_mode_indicator = () => {
    const doc = window.document;
    const host =
      doc?.getElementById("statusTextBox") ?? doc?.getElementById("status-bar");
    if (!host) return null;
    let el = doc.getElementById("tbkeys-mode-indicator");
    if (el) return el;
    el = doc.createXULElement
      ? doc.createXULElement("label")
      : doc.createElement("label");
    el.id = "tbkeys-mode-indicator";
    el.className = "statusbarpanel";
    el.setAttribute("crop", "end");
    host.insertBefore(el, host.firstChild);
    return el;
  };

  // Known gap: the pending chord (e.g. "m" awaiting "r") is not shown - it
  // lives inside Mousetrap's internal buffer and isn't exposed to us.
  /**
   * Repaints the mode/count indicator from window.vim and window.count; a no-op where the status bar is absent.
   */
  tk.repaint_mode = () => {
    const el = tk.ensure_mode_indicator();
    if (!el) return;
    const parts = [tk.is_visual() ? "-- VISUAL --" : "-- NORMAL --"];
    if (tk.has_count()) parts.push(String(window.count));
    if (tk.folder_search_active) {
      const matches = window.folderSearchMatches || [];
      const pos = matches.length ? (window.folderSearchIndex ?? 0) + 1 : 0;
      parts.push(`/${tk.search_term} [${pos}/${matches.length}]`);
    }
    const text = parts.join(" ");
    if (el.namespaceURI?.includes("there.is.only.xul")) {
      el.setAttribute("value", text);
    } else {
      el.textContent = text;
    }
  };
})(window.tk);
