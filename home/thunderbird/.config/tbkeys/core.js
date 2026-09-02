// Shared logic behind home/thunderbird/tbkeys/keys.json, loaded into each mail
// window by betterbird.cfg. Creates a fresh window.tk on every load so a
// reload cleanly replaces the last; other modules populate this namespace.
(function () {
  "use strict";

  window.tk?.whichkey_teardown?.();
  window.tk?.ui_teardown?.();
  window.tk?.command_teardown?.();
  window.tk = {};
})();

(function (tk) {
  "use strict";

  tk.PROJECTS_FOLDER = "Projects";
  tk.TBKEYS_ADDON_ID = "tbkeys@addons.thunderbird.net";
  tk.MARK_PREF = "tbkeys.folder_marks";
  // Excludes d, f, g, m, z: chord leaders elsewhere in keys.json.
  tk.MARK_LETTERS = "abcehijklnopqrstuvwxy";

  // Must match MODULE_MANIFEST in betterbird.cfg; :reload depends on the two agreeing.
  tk.MODULE_MANIFEST = [
    "core.js",
    "selection.js",
    "folders.js",
    "motions.js",
    "navigation.js",
    "actions.js",
    "search.js",
    "command.js",
    "ui.js",
    "whichkey.js",
  ];

  // -- window/tree accessors --------------------------------------------

  /**
   * @returns {Element} the thread tree element, or undefined if no tab is open
   */
  tk.get_thread_tree = () => window.gTabmail?.currentAbout3Pane?.threadTree;

  /**
   * @returns {Element} the folder tree element, or undefined if no tab is open
   */
  tk.get_folder_tree = () => window.gTabmail?.currentAbout3Pane?.folderTree;

  /**
   * @returns {Document} the current mail tab's document, or null if unavailable
   */
  tk.get_inbox_doc = () =>
    window?.gTabmail?.currentAbout3Pane?.document || null;

  /**
   * @returns {Window} the message pane's content window, or null if unavailable
   */
  tk.get_message_content_window = () =>
    window?.gTabmail?.currentAboutMessage?.getMessagePaneBrowser?.()
      ?.contentWindow || null;

  /**
   * Walks document.activeElement up the parent chain to find the enclosing tree.
   * @returns {Element} the threadTree or folderTree element it is inside, or null
   */
  tk.get_focused_element = () => {
    const doc = window.gTabmail?.currentAbout3Pane?.document;
    if (!doc) return null;
    let e = doc.activeElement;
    while (e) {
      if (e.id === "threadTree" || e.id === "folderTree") return e;
      e = e.parentElement;
    }
    return null;
  };

  // -- count prefix ---------------------------------------------------------

  /**
   * @returns {boolean} true when a count prefix is actually pending, as opposed to peek_count's default of 1
   */
  tk.has_count = () =>
    typeof window.count === "number" &&
    Number.isFinite(window.count) &&
    window.count > 0;

  /**
   * @returns {number} the pending count prefix, or 1 if none is set
   */
  tk.peek_count = () => (tk.has_count() ? window.count : 1);
  tk.reset_count = () => {
    window.count = undefined;
    tk.repaint_mode();
  };

  /**
   * @param {string} cmd - goDoCommand command id
   * @param {number} n - number of times to run it
   */
  tk.repeat_command = (cmd, n) => {
    for (let i = 0; i < n; i++) window.goDoCommand(cmd);
  };

  // -- last-action recording for . -----------------------------------------

  tk.last_action = null;
  tk.effective_count = null;

  /**
   * Wraps window[name] so invoking it records itself as the last action, for . to replay; delegates to the original with no behavior change. Records the count the action actually consumed, which a visual-mode range caps at 1, rather than the count that was merely pending when it started.
   * @param {string} name - name of a window.tk_* function to wrap in place
   */
  tk.record_action = (name) => {
    const original = window[name];
    window[name] = (...args) => {
      tk.last_action = { name, count: tk.peek_count() };
      tk.effective_count = null;
      const result = original(...args);
      if (typeof tk.effective_count === "number")
        tk.last_action.count = tk.effective_count;
      return result;
    };
  };

  /**
   * @param {number} n - digit pressed
   * @returns {Function} handler that appends the digit to the pending count prefix
   */
  tk.digit = (n) => () => {
    window.count =
      typeof window.count === "number" && Number.isFinite(window.count)
        ? window.count * 10 + n
        : n === 0
          ? window.count
          : n;
    tk.repaint_mode();
  };

  // -- message state commands ---------------------------------------------

  /**
   * @param {Element} tt - the thread tree
   * @returns {Object} header of the currently selected message, or undefined
   */
  tk.get_current_hdr = (tt) => tt?.view?.getMsgHdrAt?.(tt.currentIndex);

  /**
   * Runs an nsMsgViewCommandType command over the view's whole current selection. These name the state to reach rather than toggling, so a command that fires more than once still lands where it was aimed.
   * @param {Element} tt - the thread tree
   * @param {string} name - nsMsgViewCommandType member name
   */
  tk.run_view_command = (tt, name) => {
    const cmd = window.Ci?.nsMsgViewCommandType?.[name];
    if (cmd !== undefined) tt?.view?.doCommand?.(cmd);
  };

  tk.read_snapshot = null;

  /**
   * Records the read state of every selected message as a chord opens. Suppressing the leader key should stop Thunderbird flipping it at all, so this only matters wherever preventDefault fails to reach the native shortcut.
   */
  tk.snapshot_read_state = () => {
    const hdrs = tk.get_thread_tree()?.view?.getSelectedMsgHdrs?.() ?? [];
    tk.read_snapshot = hdrs.length
      ? hdrs.map((hdr) => ({ hdr, is_read: hdr.isRead }))
      : null;
  };

  /**
   * Restores the read state sampled when the chord opened, then clears it. Writes each header back through its own folder rather than issuing one selection-wide command, so a selection that has since changed, or was never uniform, still lands on exactly what was sampled.
   */
  tk.restore_read_state = () => {
    const snapshot = tk.read_snapshot;
    tk.read_snapshot = null;
    if (!snapshot) return;
    for (const { hdr, is_read } of snapshot) {
      if (hdr.isRead !== is_read)
        hdr.folder?.markMessagesRead?.([hdr], is_read);
    }
  };

  // -- flat tk_* functions for keys.json "func:" bindings ------------------

  for (let i = 0; i <= 9; i++) {
    window[`tk_digit_${i}`] = tk.digit(i);
  }
})(window.tk);
