// Higher-level message navigation: unread/thread/starred/attachment stepping,
// focus switching, tab navigation, and generic row matching.
(function (tk) {
  "use strict";

  /**
   * Runs a Thunderbird navigation command count times, then resyncs visual-mode state from where the selection landed; leaves visual mode if the command crossed into another folder.
   * @param {string} cmd - goDoCommand command id that moves the selection
   */
  tk.run_navigation_command = (cmd) => {
    const folder_before =
      window.gTabmail?.currentAbout3Pane?.gFolder?.URI ?? null;
    const n = tk.peek_count();
    tk.reset_count();
    tk.repeat_command(cmd, n);
    if (!tk.is_visual()) return;
    const tt = tk.get_thread_tree();
    const folder_after =
      window.gTabmail?.currentAbout3Pane?.gFolder?.URI ?? null;
    if (folder_before !== folder_after) {
      window.vim = "normal";
      window.visualAnchor = undefined;
      window.visualEnd = undefined;
      tk.repaint_mode();
      return;
    }
    if (typeof tt?.currentIndex !== "number" || tt.currentIndex < 0) return;
    const anchor =
      typeof window.visualAnchor === "number"
        ? window.visualAnchor
        : tt.currentIndex;
    tt._selectRange(anchor, tt.currentIndex, false);
    window.visualEnd = tt.currentIndex;
  };

  // -- row stepping -----------------------------------------------------------

  /**
   * Selects the count'th next/previous row matching predicate, stopping at the folder's edge without wrapping or crossing folders; extends the visual selection like j/k when in visual mode.
   * @param {number} direction - 1 for next, -1 for previous
   * @param {Function} predicate - (hdr, idx, view) => boolean, tested per row
   */
  tk.step_matching = (direction, predicate) => {
    const tt = tk.get_thread_tree();
    const view = tt?.view;
    if (!tt || !view) {
      tk.reset_count();
      return;
    }
    const is_visual = tk.is_visual();
    const row_count = view.rowCount;
    const start =
      is_visual && typeof window.visualEnd === "number"
        ? window.visualEnd
        : tt.currentIndex;
    let idx = start;
    let found = start;
    for (let remaining = tk.peek_count(); remaining > 0; remaining--) {
      for (idx += direction; idx >= 0 && idx < row_count; idx += direction) {
        if (predicate(view.getMsgHdrAt(idx), idx, view)) break;
      }
      if (idx < 0 || idx >= row_count) break;
      found = idx;
    }
    tk.reset_count();
    if (found === start) return;
    if (is_visual) {
      const anchor =
        typeof window.visualAnchor === "number" ? window.visualAnchor : start;
      tt._selectRange(anchor, found, false);
      window.visualEnd = found;
    } else {
      tt._selectSingle(found);
    }
  };

  // -- flat tk_* functions for keys.json "func:" bindings ------------------

  window.tk_focus_folder_tree = () =>
    window.gTabmail?.currentAbout3Pane?.folderTree?.focus?.();
  window.tk_focus_thread_tree = () =>
    window.gTabmail?.currentAbout3Pane?.threadTree?.table?.body?.focus?.();
  window.tk_focus_message_pane = () =>
    window.gTabmail?.currentAboutMessage?.getMessagePaneBrowser?.()?.focus?.();

  window.tk_next_tab = () =>
    window.document
      .getElementById("tabmail-tabs")
      ?.advanceSelectedTab?.(-1, true);
  window.tk_prev_tab = () =>
    window.document
      .getElementById("tabmail-tabs")
      ?.advanceSelectedTab?.(1, true);

  window.tk_toggle_starred_filter = () =>
    window.gTabmail?.currentAbout3Pane?.document
      ?.getElementById("qfb-starred")
      ?.click();

  window.tk_next_unread_thread = () =>
    tk.step_matching(1, (hdr) => hdr && !hdr.isRead);
  window.tk_prev_unread_thread = () =>
    tk.step_matching(-1, (hdr) => hdr && !hdr.isRead);

  window.tk_next_thread_root = () =>
    tk.step_matching(1, (hdr, idx, view) => view.isContainer(idx));
  window.tk_prev_thread_root = () =>
    tk.step_matching(-1, (hdr, idx, view) => view.isContainer(idx));

  window.tk_next_starred = () => tk.run_navigation_command("cmd_nextFlaggedMsg");
  window.tk_prev_starred = () =>
    tk.run_navigation_command("cmd_previousFlaggedMsg");
  window.tk_next_unread_any_folder = () =>
    tk.run_navigation_command("cmd_nextUnreadMsg");
  window.tk_prev_unread_any_folder = () =>
    tk.run_navigation_command("cmd_previousUnreadMsg");

  const has_attachment = (hdr) =>
    !!(hdr && hdr.flags & window.Ci?.nsMsgMessageFlags?.Attachment);
  window.tk_next_attachment = () => tk.step_matching(1, has_attachment);
  window.tk_prev_attachment = () => tk.step_matching(-1, has_attachment);
})(window.tk);
