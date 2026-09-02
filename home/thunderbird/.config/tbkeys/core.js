// Shared logic behind home/thunderbird/tbkeys/keys.json, loaded into each mail
// window by betterbird.cfg. Creates a fresh window.tk on every load so a
// reload cleanly replaces the last; other modules populate this namespace.
(function () {
  "use strict";

  window.tk?.whichkey_teardown?.();
  window.tk = {};
})();

(function (tk) {
  "use strict";

  tk.PROJECTS_FOLDER = "Projects";
  tk.MARK_PREF = "tbkeys.folder_marks";
  // Excludes d, f, g, m, z: chord leaders elsewhere in keys.json.
  tk.MARK_LETTERS = "abcehijklnopqrstuvwxy";

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

  /**
   * Wraps window[name] so invoking it records itself (and the count it saw) as the last action, for . to replay; delegates to the original with no behavior change.
   * @param {string} name - name of a window.tk_* function to wrap in place
   */
  tk.record_action = (name) => {
    const original = window[name];
    window[name] = (...args) => {
      tk.last_action = { name, count: tk.peek_count() };
      return original(...args);
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

  // -- message read-state toggling ----------------------------------------

  /**
   * @param {Element} tt - the thread tree
   * @returns {Object} header of the currently selected message, or undefined
   */
  tk.get_current_hdr = (tt) => tt?.view?.getMsgHdrAt?.(tt.currentIndex);

  /**
   * @param {Object} hdr - message header to toggle, or undefined/null to no-op
   */
  tk.toggle_read_state = (hdr) => {
    if (hdr)
      window.goDoCommand(hdr.isRead ? "cmd_markAsUnread" : "cmd_markAsRead");
  };

  // -- flat tk_* functions for keys.json "func:" bindings ------------------

  for (let i = 0; i <= 9; i++) {
    window[`tk_digit_${i}`] = tk.digit(i);
  }
})(window.tk);
