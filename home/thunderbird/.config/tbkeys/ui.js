// Persistent mode/count/status indicator in the mail window's status bar,
// and the insert-mode tracking that follows focus in and out of text fields.
(function (tk) {
  "use strict";

  const MODE_LABELS = {
    normal: "-- NORMAL --",
    visual: "-- VISUAL --",
    insert: "-- INSERT --",
  };

  const MODE_COLORS = {
    normal: "var(--color-yellow-50)",
    insert: "var(--color-red-50)",
    visual: "var(--color-orange-50)",
  };

  const QUICK_FILTER_ID = "qfb-qs-textbox";

  /**
   * @returns {Element} the injected mode/count indicator, or null where no suitable host exists
   */
  tk.ensure_mode_indicator = () => {
    const doc = window.document;
    const host =
      doc?.getElementById("statusTextBox") ?? doc?.getElementById("status-bar");
    let el = doc.getElementById("tbkeys-mode-indicator");
    if (el) return el;
    if (!host) {
      if (doc.documentElement?.getAttribute("windowtype") !== "msgcompose")
        return null;
      el = doc.createXULElement
        ? doc.createXULElement("label")
        : doc.createElement("label");
      el.id = "tbkeys-mode-indicator";
      el.style.cssText =
        "position:fixed; right:12px; bottom:12px; z-index:2147483647; " +
        "font:14px monospace; padding:4px 8px; background:var(--layout-background-0);";
      (doc.body ?? doc.documentElement).appendChild(el);
      return el;
    }
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
    const parts = [MODE_LABELS[window.vim] ?? MODE_LABELS.normal];
    if (tk.has_count()) parts.push(String(window.count));
    if (tk.folder_search_active) {
      const matches = window.folderSearchMatches || [];
      const pos = matches.length ? (window.folderSearchIndex ?? 0) + 1 : 0;
      parts.push(`/${tk.search_term} [${pos}/${matches.length}]`);
    }
    el.style.color = MODE_COLORS[window.vim] ?? MODE_COLORS.normal;
    const text = parts.join(" ");
    if (el.namespaceURI?.includes("there.is.only.xul")) {
      el.setAttribute("value", text);
    } else {
      el.textContent = text;
    }
  };

  let status_timer = null;
  tk.show_status = (message) => {
    const el = tk.ensure_mode_indicator();
    if (!el) return;
    if (status_timer) window.clearTimeout(status_timer);
    if (el.namespaceURI?.includes("there.is.only.xul"))
      el.setAttribute("value", message);
    else el.textContent = message;
    status_timer = window.setTimeout(() => {
      status_timer = null;
      tk.repaint_mode();
    }, 1800);
  };

  // -- insert mode ----------------------------------------------------------

  tk.mode_before_insert = null;

  /**
   * @returns {boolean} true when focus sits in a field that takes typed text, in either the chrome window or the 3-pane document
   */
  tk.is_text_focus = () =>
    !!(
      tk.is_compose_body_focus?.() ||
      tk.is_text_input?.(window.document?.activeElement) ||
      tk.is_text_input?.(tk.get_inbox_doc()?.activeElement)
    );

  /**
   * Enters insert mode while a text field holds focus and returns to the mode that was current before it, so a visual selection survives a trip through the filter box.
   */
  tk.sync_insert_mode = () => {
    const in_text = tk.is_text_focus();
    if (in_text) {
      if (window.__tbkeys_one_command_normal) {
        tk.repaint_mode();
        return;
      }
      if (window.vim === "insert") return;
      tk.mode_before_insert = window.vim ?? "normal";
      window.vim = "insert";
    } else {
      if (window.vim !== "insert") return;
      window.vim = tk.mode_before_insert ?? "normal";
      tk.mode_before_insert = null;
    }
    tk.repaint_mode();
  };

  // focusout fires before activeElement moves, so recheck on the next tick.
  tk.focus_handler = (e) =>
    e.type === "focusout"
      ? window.setTimeout(tk.sync_insert_mode, 0)
      : tk.sync_insert_mode();

  /**
   * @param {Element} el - element to check
   * @returns {boolean} true if the element or an ancestor is the quick filter input
   */
  tk.is_quick_filter = (el) => {
    for (let node = el; node; node = node.parentElement) {
      if (node.id === QUICK_FILTER_ID) return true;
    }
    return false;
  };

  /**
   * Sends focus to the thread tree when Enter is pressed in the quick filter, which filters as you type and has nothing left to submit.
   * @param {KeyboardEvent} e
   */
  tk.quick_filter_enter_handler = (e) => {
    if (e.key !== "Enter" || e.ctrlKey || e.altKey || e.metaKey) return;
    if (!tk.is_quick_filter(e.target)) return;
    e.preventDefault();
    window.tk_focus_thread_tree?.();
    tk.sync_insert_mode();
  };

  window.addEventListener("focusin", tk.focus_handler, { capture: true });
  window.addEventListener("focusout", tk.focus_handler, { capture: true });
  window.addEventListener("keydown", tk.quick_filter_enter_handler, {
    capture: true,
  });

  tk.ui_teardown = () => {
    if (status_timer) window.clearTimeout(status_timer);
    window.removeEventListener("focusin", tk.focus_handler, { capture: true });
    window.removeEventListener("focusout", tk.focus_handler, { capture: true });
    window.removeEventListener("keydown", tk.quick_filter_enter_handler, {
      capture: true,
    });
  };
})(window.tk);
