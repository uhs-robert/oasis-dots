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
      tk.exit_visual();
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

  // -- sort -----------------------------------------------------------------

  tk.SORT_COLUMNS = {
    date: "dateCol",
    subject: "subjectCol",
    sender: "senderCol",
    recipient: "recipientCol",
    received: "receivedCol",
    size: "sizeCol",
    tags: "tagsCol",
    account: "accountCol",
    priority: "priorityCol",
    status: "statusCol",
    location: "locationCol",
    unread: "unreadButtonColHeader",
    starred: "flaggedCol",
    attachment: "attachmentCol",
    junk: "junkStatusCol",
  };

  /**
   * @param {string} name - key into tk.SORT_COLUMNS
   * @returns {string} error message on failure, undefined on success
   */
  tk.sort_by = (name) => {
    if (!Object.hasOwn(tk.SORT_COLUMNS, name)) return `Unknown sort "${name}"`;
    const column_id = tk.SORT_COLUMNS[name];
    const controller = window.gTabmail?.currentAbout3Pane?.sortController;
    if (!controller) return "No thread pane to sort";
    if (!controller.sortThreadPane(column_id))
      return `Column "${name}" is not in the current view`;
  };

  /**
   * @returns {string} error message on failure, undefined on success
   */
  tk.sort_reverse = () => {
    const controller = window.gTabmail?.currentAbout3Pane?.sortController;
    if (!controller) return "No thread pane to sort";
    controller.reverseSortThreadPane();
  };

  // -- flat tk_* functions for keys.json "func:" bindings ------------------

  window.tk_focus_folder_tree = () =>
    window.gTabmail?.currentAbout3Pane?.folderTree?.focus?.();
  window.tk_focus_thread_tree = () =>
    window.gTabmail?.currentAbout3Pane?.threadTree?.table?.body?.focus?.();
  window.tk_focus_message_pane = () =>
    window.gTabmail?.currentAboutMessage?.getMessagePaneBrowser?.()?.focus?.();

  window.tk_goto_extensions = () => {
    tk.reset_count();
    window.openAddonsMgr?.("addons://list/extension");
  };
  // The detail view splits its param on "/", so this lands on tbkeys' own
  // options pane rather than its card.
  window.tk_goto_config = () => {
    tk.reset_count();
    window.openAddonsMgr?.(`addons://detail/${tk.TBKEYS_ADDON_ID}/preferences`);
  };

  window.tk_next_tab = () =>
    window.document
      .getElementById("tabmail-tabs")
      ?.advanceSelectedTab?.(-1, true);
  window.tk_prev_tab = () =>
    window.document
      .getElementById("tabmail-tabs")
      ?.advanceSelectedTab?.(1, true);

  window.tk_toggle_starred_filter = () => {
    tk.reset_count();
    window.gTabmail?.currentAbout3Pane?.document
      ?.getElementById("qfb-starred")
      ?.click();
  };

  // View commands are handled by about:3pane, not the top-level chrome
  // window. The unread view command is disabled for virtual folders, so use
  // the Quick Filter Bar's equivalent there (including unified folders).
  const current_pane = () => window.gTabmail?.currentAbout3Pane;
  const is_virtual_folder = (pane) =>
    !!(
      pane?.gFolder?.flags &
      (window.Ci?.nsMsgFolderFlags?.Virtual ?? 0)
    );

  const apply_quick_filter = (pane, name, value) => {
    const bar = pane?.quickFilterBar;
    if (!bar?.filterer) return "No quick filter bar";
    bar._showFilterBar?.(true);
    bar.filterer.setFilterValue(name, value);
    bar.reflectFiltererState?.();
    bar.updateSearch?.();
  };

  tk.filter_unread = () => {
    tk.reset_count();
    const pane = current_pane();
    if (!pane) return "No message pane to filter";
    if (is_virtual_folder(pane))
      return apply_quick_filter(pane, "unread", true);
    const controller = pane.commandController;
    if (!controller) return "No message pane command controller";
    controller.doCommand("cmd_viewUnreadMsgs");
  };

  tk.filter_all = () => {
    tk.reset_count();
    const pane = current_pane();
    if (!pane) return "No message pane to filter";
    const controller = pane?.commandController;
    if (!controller) return "No message pane command controller";
    controller.doCommand("cmd_viewAllMsgs");
    pane.quickFilterBar?._resetFilterState?.();
  };

  window.tk_filter_unread = () => {
    const error = tk.filter_unread();
    if (error) window.alert(error);
  };
  window.tk_filter_all = () => {
    const error = tk.filter_all();
    if (error) window.alert(error);
  };

  for (const name of Object.keys(tk.SORT_COLUMNS)) {
    window[`tk_sort_${name}`] = () => {
      tk.reset_count();
      const error = tk.sort_by(name);
      if (error) window.alert(error);
    };
  }
  window.tk_sort_reverse = () => {
    tk.reset_count();
    const error = tk.sort_reverse();
    if (error) window.alert(error);
  };

  window.tk_next_unread_thread = () =>
    tk.step_matching(1, (hdr) => hdr && !hdr.isRead);
  window.tk_prev_unread_thread = () =>
    tk.step_matching(-1, (hdr) => hdr && !hdr.isRead);

  window.tk_next_thread_root = () =>
    tk.step_matching(1, (hdr, idx, view) => view.isContainer(idx));
  window.tk_prev_thread_root = () =>
    tk.step_matching(-1, (hdr, idx, view) => view.isContainer(idx));

  window.tk_next_starred = () =>
    tk.run_navigation_command("cmd_nextFlaggedMsg");
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
