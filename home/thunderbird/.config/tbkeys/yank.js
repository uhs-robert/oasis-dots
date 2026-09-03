// Non-mutating message inspection and Vim-style yanks. Clipboard writes use
// Thunderbird's privileged XPCOM clipboard API rather than page text APIs.
(function (tk) {
  "use strict";

  const clipboard_write = (text) => {
    const value = String(text ?? "");
    if (!value) return false;
    try {
      const Cc =
        window.Cc ??
        window.Components?.classes ??
        (typeof Components !== "undefined" ? Components.classes : null);
      const Ci =
        window.Ci ??
        window.Components?.interfaces ??
        globalThis.Ci ??
        (typeof Components !== "undefined" ? Components.interfaces : null);
      if (!Cc || !Ci)
        throw new Error("Thunderbird clipboard services unavailable");
      Cc["@mozilla.org/widget/clipboardhelper;1"]
        .getService(Ci.nsIClipboardHelper)
        .copyString(value);
      return true;
    } catch (error) {
      tk.show_status?.(`YANK FAILED: ${error}`);
      return false;
    }
  };

  const report = (label, value, count = 1) => {
    if (!value) {
      tk.show_status?.(`YANK FAILED: no ${label}`);
      return;
    }
    if (clipboard_write(value))
      tk.show_status?.(`YANKED ${count > 1 ? `${count} ` : ""}${label}`);
  };

  const selected_headers = () => {
    const tree = tk.get_thread_tree();
    if (!tree) return [];
    const range = tk.resolve_action_range(tree);
    if (range.is_visual && typeof range.top_index === "number") {
      const end = range.cursor_index ?? range.top_index;
      const first = Math.min(range.top_index, end);
      const last = Math.max(range.top_index, end);
      const headers = [];
      for (let i = first; i <= last; i++) {
        const header = tree.view?.getMsgHdrAt?.(i);
        if (header) headers.push(header);
      }
      return headers;
    }
    const selected = tree.view?.getSelectedMsgHdrs?.() ?? [];
    return selected.length ? selected : [range.anchor_hdr].filter(Boolean);
  };

  const sender_address = (header) => {
    const author = header?.author ?? "";
    try {
      const parsed = window.MailServices?.headerParser?.makeFromDisplayAddress?.(
        author,
      );
      if (parsed?.length && parsed[0].email) return parsed[0].email;
    } catch (_) {
      // Fall through to conservative address extraction.
    }
    return author.match(/<([^>]+)>/)?.[1] ?? author;
  };

  const yank_headers = (label, read) => {
    const headers = selected_headers();
    if (!headers.length) {
      tk.show_status?.(`YANK FAILED: no message for ${label}`);
      return;
    }
    const values = headers.map(read).map((value) => String(value ?? ""));
    if (values.some((value) => !value)) {
      tk.show_status?.(`YANK FAILED: ${label} unavailable`);
      return;
    }
    report(label, values.join("\n"), values.length);
  };

  window.tk_yank_subject = () => yank_headers("subject", (h) => h.subject);
  window.tk_yank_sender = () => yank_headers("sender", (h) => h.author);
  window.tk_yank_sender_address = () =>
    yank_headers("sender address", sender_address);
  window.tk_yank_message_id = () =>
    yank_headers("Message-ID", (h) => h.messageId);

  window.tk_yank_content = () => {
    const message_window = tk.get_message_content_window?.();
    const selection = message_window?.getSelection?.()?.toString?.()?.trim();
    if (selection) {
      report("selection", selection);
      return;
    }
    const body = message_window?.document?.body;
    const content = (body?.innerText ?? body?.textContent ?? "").trim();
    if (!content) {
      tk.show_status?.("YANK FAILED: no message content");
      return;
    }
    // Body yanks use the displayed message only; metadata yanks support
    // visual multi-selection.
    report("message content", content);
  };
})(window.tk);
