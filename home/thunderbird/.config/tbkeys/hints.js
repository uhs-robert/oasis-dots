// Cross-document Vimium-style hints for visible Thunderbird controls.
// The module owns its complete lifecycle; whichkey.js remains documentation only.
(function (tk) {
  "use strict";

  const ALPHABET = "asdfghjklqwertyuiopzxcvbnm";
  const ACTIONS = {
    f: { label: "focus", run: (target) => target.focus() },
    c: { label: "activate", run: (target) => target.activate() },
    y: { label: "yank", run: (target) => target.copy() },
  };
  const ACTION_LABELS = Object.entries(ACTIONS)
    .map(([key, action]) => `${key}: ${action.label}`)
    .join("  ");
  const TARGET_SELECTOR = [
    "a[href]", "button", "input:not([type='hidden'])", "select", "textarea",
    "[role='button']", "[role='link']", "[role='menuitem']", "[role='option']",
    "[role='tab']", "[role='treeitem']", "[role='row']", "toolbarbutton",
    "menulist", "menuitem", "richlistitem", "treeitem",
  ].join(",");
  let session = null;

  const target_name = (element) =>
    (element.getAttribute?.("aria-label") || element.getAttribute?.("title") ||
      element.getAttribute?.("label") || element.innerText || element.textContent ||
      element.value || "").replace(/\s+/g, " ").trim();

  const visible = (element, doc) => {
    if (!element || element.disabled || element.getAttribute?.("aria-disabled") === "true")
      return false;
    for (let node = element; node && node !== doc; node = node.parentElement) {
      if (node.hidden || node.getAttribute?.("aria-hidden") === "true") return false;
      const style = node.ownerDocument.defaultView?.getComputedStyle(node);
      if (style && (style.display === "none" || style.visibility === "hidden")) return false;
    }
    const rect = element.getBoundingClientRect?.();
    return !!rect && rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.right > 0 &&
      rect.top < (doc.defaultView?.innerHeight ?? Infinity) &&
      rect.left < (doc.defaultView?.innerWidth ?? Infinity);
  };

  const screen_rect = (element) => {
    const rect = element.getBoundingClientRect();
    let doc = element.ownerDocument;
    let left = rect.left;
    let top = rect.top;
    while (doc && doc !== window.document) {
      const frame = doc.defaultView?.frameElement;
      if (!frame) return null;
      const frame_rect = frame.getBoundingClientRect();
      left += frame_rect.left;
      top += frame_rect.top;
      doc = frame.ownerDocument;
    }
    return { left, top, width: rect.width, height: rect.height };
  };

  const documents = () => {
    const found = [];
    const seen = new Set();
    const visit = (doc) => {
      if (!doc || seen.has(doc)) return;
      seen.add(doc);
      found.push(doc);
      for (const frame of doc.querySelectorAll?.("iframe,frame,object,embed") ?? []) {
        try { visit(frame.contentDocument); } catch (_) { /* inaccessible child */ }
      }
      for (const host of doc.querySelectorAll?.("*") ?? [])
        if (host.shadowRoot) visit(host.shadowRoot);
    };
    visit(window.document);
    visit(tk.get_inbox_doc?.());
    visit(tk.get_message_content_window?.()?.document);
    return found;
  };

  const target_for = (element, doc) => {
    const anchor = element.closest?.("a[href]");
    const copy_value = () => anchor?.href || target_name(element);
    return {
      element, doc, rect: screen_rect(element), name: target_name(element) || "target",
      focus: () => element.focus?.(), activate: () => element.click?.(),
      copy: () => {
        const value = copy_value();
        try {
          const Cc = window.Cc ?? window.Components?.classes;
          const Ci = window.Ci ?? window.Components?.interfaces;
          if (!value) throw new Error("target has no copyable value");
          const helper = Cc?.["@mozilla.org/widget/clipboardhelper;1"]
            ?.getService(Ci?.nsIClipboardHelper);
          if (!helper?.copyString) throw new Error("clipboard service unavailable");
          helper.copyString(value);
          tk.show_status?.(`YANKED ${anchor?.href ? "URL" : "target text"}`);
        } catch (error) {
          tk.show_status?.(`YANK FAILED: ${error.message ?? error}`);
        }
      },
    };
  };

  const discover = (docs) => {
    const targets = [];
    const elements = new Set();
    for (const doc of docs) {
      for (const element of doc.querySelectorAll?.(TARGET_SELECTOR) ?? []) {
        if (elements.has(element) || !visible(element, doc)) continue;
        const target = target_for(element, doc);
        if (target.rect) { elements.add(element); targets.push(target); }
      }
    }
    return targets;
  };

  const labels = (count) => {
    const result = [];
    for (let i = 0; i < count; i++) {
      let n = i, label = "";
      do { label = ALPHABET[n % ALPHABET.length] + label; n = Math.floor(n / ALPHABET.length) - 1; }
      while (n >= 0);
      result.push(label);
    }
    return result;
  };

  const panel = () => {
    let el = window.document.getElementById("tbkeys-hints");
    if (el) return el;
    el = window.document.createElement("div");
    el.id = "tbkeys-hints";
    el.style.cssText = "position:fixed;inset:0;z-index:2147483647;pointer-events:none;";
    (window.document.body ?? window.document.documentElement).appendChild(el);
    return el;
  };

  const render = () => {
    const host = panel();
    host.textContent = "";
    const colors = tk.whichkey_colors ?? { bg: "Canvas", key: "HighlightText", border: "CanvasText" };
    for (const target of session.targets) {
      const badge = window.document.createElement("span");
      badge.textContent = target.label;
      badge.setAttribute("aria-label", `${target.label}: ${target.name}`);
      const r = target.rect;
      badge.style.cssText = `position:fixed;left:${r.left}px;top:${r.top}px;background:${colors.bg};` +
        `color:${colors.key};border:1px solid ${colors.border};font:bold 12px monospace;` +
        "line-height:14px;padding:0 2px;white-space:nowrap;";
      if (session.query && !target.label.startsWith(session.query)) badge.hidden = true;
      host.appendChild(badge);
    }
    host.style.display = "block";
  };

  const close = () => {
    if (!session) return;
    for (const [doc, handler, press_handler] of session.listeners) {
      doc.removeEventListener("keydown", handler, true);
      doc.removeEventListener("keypress", press_handler, true);
    }
    window.removeEventListener("blur", session.close);
    window.document.getElementById("tbkeys-hints")?.remove();
    session = null;
    tk.repaint_mode?.();
  };

  const suppress_next_keypress = (doc) => {
    const handler = (event) => {
      event.preventDefault();
      event.stopImmediatePropagation();
      doc.removeEventListener("keypress", handler, true);
    };
    doc.addEventListener("keypress", handler, true);
  };

  const cancel_from_key = (event) => {
    const doc = event.currentTarget;
    close();
    suppress_next_keypress(doc);
  };

  const activate = (target, event) => {
    const action = session.action;
    const doc = event.currentTarget;
    close();
    suppress_next_keypress(doc);
    try { action.run(target); } catch (error) { tk.show_status?.(`HINT FAILED: ${error}`); }
  };

  const key_handler = (event) => {
    if (!session) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (event.key === "Escape") return cancel_from_key(event);
    if (session.phase === "action") {
      const action = ACTIONS[event.key.toLowerCase()];
      if (!action) return cancel_from_key(event);
      session.phase = "target";
      session.action = action;
      session.query = "";
      tk.show_status?.(`HINT ${action.label}: type a label, Esc cancels`);
      return render();
    }
    if (event.key === "Backspace") { session.query = session.query.slice(0, -1); return render(); }
    if (event.key.length !== 1 || !ALPHABET.includes(event.key.toLowerCase())) return cancel_from_key(event);
    session.query += event.key.toLowerCase();
    const matches = session.targets.filter((target) => target.label.startsWith(session.query));
    if (!matches.length) return cancel_from_key(event);
    if (matches.length === 1 && matches[0].label === session.query) return activate(matches[0], event);
    render();
  };

  // tbkeys/Mousetrap may still observe keypress after capture-phase keydown.
  // Consume it without processing the label a second time.
  const keypress_handler = (event) => {
    if (!session) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  };

  const open = (action, phase = "target") => {
    close();
    const docs = documents();
    const targets = discover(docs);
    if (!targets.length) return tk.show_status?.("HINT: no visible actionable targets");
    labels(targets.length).forEach((label, i) => { targets[i].label = label; });
    session = { targets, action, phase, query: "", listeners: [], close };
    for (const doc of docs) {
      doc.addEventListener("keydown", key_handler, true);
      doc.addEventListener("keypress", keypress_handler, true);
      session.listeners.push([doc, key_handler, keypress_handler]);
    }
    window.addEventListener("blur", close, { once: true });
    render();
    tk.show_status?.(phase === "action" ? `HINT ACTION: ${ACTION_LABELS}` : "HINT: type a label, Esc cancels");
  };

  tk.hints_close = close;
  window.tk_hints = () => open(ACTIONS.c);
  window.tk_hints_advanced = () => open(null, "action");
  const tab_handler = () => close();
  const unload_handler = () => close();
  window.addEventListener("TabSelect", tab_handler, true);
  window.addEventListener("unload", unload_handler, { once: true });
  tk.hints_teardown = () => {
    close();
    window.removeEventListener("TabSelect", tab_handler, true);
    window.removeEventListener("unload", unload_handler);
  };
})(window.tk);
