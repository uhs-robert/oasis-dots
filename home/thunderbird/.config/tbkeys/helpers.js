// Shared logic behind home/thunderbird/tbkeys/keys.json, loaded into each mail
// window by betterbird.cfg. One IIFE, so a re-load cleanly replaces the last.
(function () {
  "use strict";

  const tk = {};
  const PROJECTS_FOLDER = "Projects";
  const MARK_PREF = "tbkeys.folder_marks";
  // Excludes d, f, g, m, z: chord leaders elsewhere in keys.json.
  const MARK_LETTERS = "abcehijklnopqrstuvwxy";

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
   * @param {string} url - folder URI to resolve
   * @returns {Object} the matching folder, or undefined if not found
   */
  tk.lookup_folder = (url) =>
    window.MailServices?.folderLookup?.getFolderForURL?.(url);

  /**
   * @param {string} url - folder URI to switch the current tab to
   */
  tk.display_folder = (url) => {
    tk.show_folder(tk.lookup_folder(url));
  };

  const JUMP_LIST_MAX = 100;
  tk.jump_back_stack = [];
  tk.jump_forward_stack = [];
  tk.jumping = false;

  /**
   * @param {Object} folder - folder to switch the current tab to, or null to no-op
   */
  tk.show_folder = (folder) => {
    if (!folder) return;
    const pane = window.gTabmail?.currentAbout3Pane;
    if (!pane) return;
    const current_uri = pane.gFolder?.URI;
    if (!tk.jumping && current_uri && current_uri !== folder.URI) {
      tk.jump_back_stack.push(current_uri);
      if (tk.jump_back_stack.length > JUMP_LIST_MAX) tk.jump_back_stack.shift();
      tk.jump_forward_stack = [];
    }
    pane.displayFolder?.(folder);
  };

  /**
   * Moves the current folder URI onto `to` and jumps to `uri` without recording new jump-list history.
   * @param {string} uri - folder URI to jump to
   * @param {string[]} to - the stack (back or forward) to push the current folder onto
   */
  tk.jump_to = (uri, to) => {
    const pane = window.gTabmail?.currentAbout3Pane;
    const current_uri = pane?.gFolder?.URI;
    const was_jumping = tk.jumping;
    tk.jumping = true;
    try {
      tk.display_folder(uri);
    } finally {
      tk.jumping = was_jumping;
    }
    if (!current_uri || pane?.gFolder?.URI === current_uri) return;
    to.push(current_uri);
    if (to.length > JUMP_LIST_MAX) to.shift();
  };

  /**
   * Searches every account for a folder named `name`, preferring an exact match over a substring one.
   * @param {string} name - folder name, matched case-insensitively
   * @returns {Object} the first matching folder, or null if none matches
   */
  tk.find_folder_by_name = (name) => {
    const target = name.toLowerCase();
    let partial = null;
    for (const account of window.MailServices?.accounts?.accounts ?? []) {
      const root = account.incomingServer?.rootFolder;
      if (!root) continue;
      for (const folder of root.descendants) {
        const folder_name = folder.name.toLowerCase();
        if (folder_name === target) return folder;
        if (!partial && folder_name.includes(target)) partial = folder;
      }
    }
    return partial;
  };

  // -- folder marks ---------------------------------------------------------

  /**
   * @returns {Object} letter to folder URI map, parsed from a single JSON pref
   */
  tk.load_marks = () => {
    try {
      const raw = window.Services?.prefs?.getStringPref?.(MARK_PREF, "{}");
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === "object" ? parsed : {};
    } catch (e) {
      return {};
    }
  };

  /**
   * @param {Object} marks - letter to folder URI map to persist
   */
  tk.save_marks = (marks) => {
    window.Services?.prefs?.setStringPref?.(MARK_PREF, JSON.stringify(marks));
  };

  /**
   * @param {string} letter - mark letter to set on the currently displayed folder
   */
  tk.set_mark = (letter) => {
    tk.reset_count();
    const uri = window.gTabmail?.currentAbout3Pane?.gFolder?.URI;
    if (!uri) return;
    const marks = tk.load_marks();
    marks[letter] = uri;
    tk.save_marks(marks);
  };

  /**
   * Jumps to the folder stored under `letter`, reporting an unset mark or a folder that no longer exists.
   * @param {string} letter - mark letter to jump to
   */
  tk.jump_to_mark = (letter) => {
    tk.reset_count();
    const uri = tk.load_marks()[letter];
    if (typeof uri !== "string" || !uri) {
      window.alert(`Mark "${letter}" is not set`);
      return;
    }
    let folder = null;
    try {
      folder = tk.lookup_folder(uri);
    } catch (e) {
      folder = null;
    }
    if (!folder) {
      window.alert(`Mark "${letter}" points to a folder that no longer exists`);
      return;
    }
    tk.show_folder(folder);
  };

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

  // -- count prefix and visual mode ---------------------------------------

  /**
   * @returns {boolean} true when vim mode is "visual"
   */
  tk.is_visual = () => window.vim === "visual";

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
    const text = parts.join(" ");
    if (el.namespaceURI?.includes("there.is.only.xul")) {
      el.setAttribute("value", text);
    } else {
      el.textContent = text;
    }
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

  // -- folder tree collapse/expand -----------------------------------------

  /**
   * Collapses every expanded row in the folder tree; omitting shouldKeep collapses everything.
   * @param {Element} ft - the folder tree
   * @param {Function} [shouldKeep] - predicate(row) => true if a row must stay expanded
   */
  tk.collapse_folder_tree = (ft, shouldKeep) => {
    let changed = true;
    while (changed) {
      changed = false;
      for (let i = 0; i < ft.rowCount; i++) {
        const row = ft.getRowAtIndex(i);
        if (
          row?.classList.contains("children") &&
          !row.classList.contains("collapsed") &&
          !(shouldKeep && shouldKeep(row))
        ) {
          ft.collapseRowAtIndex(i);
          changed = true;
          break;
        }
      }
    }
  };

  /**
   * @param {Element} ft - the folder tree
   */
  tk.expand_folder_tree = (ft) => {
    let changed = true;
    while (changed) {
      changed = false;
      for (let i = 0; i < ft.rowCount; i++) {
        const row = ft.getRowAtIndex(i);
        if (
          row?.classList.contains("children") &&
          row.classList.contains("collapsed")
        ) {
          ft.expandRowAtIndex(i);
          changed = true;
          break;
        }
      }
    }
  };

  /**
   * @param {Element} ft - the folder tree
   * @returns {Object[]} row snapshots with uri, depth, and name
   */
  tk.snapshot_folder_rows = (ft) => {
    const snapshot = [];
    for (let i = 0; i < ft.rowCount; i++) {
      const row = ft.getRowAtIndex(i);
      snapshot.push({
        uri: row.uri,
        depth: row.depth,
        name: row.nameLabel?.textContent ?? "",
      });
    }
    return snapshot;
  };

  /**
   * @param {Object[]} snapshot - row snapshots from snapshot_folder_rows
   * @param {number[]} indices - snapshot indices that must remain visible
   * @returns {Set<string>} ancestor uris needed to keep those rows visible
   */
  tk.keep_ancestors = (snapshot, indices) => {
    const keep = new Set();
    for (const mi of indices) {
      if (mi === -1) continue;
      let depth = snapshot[mi].depth;
      for (let i = mi - 1; i >= 0 && depth > 0; i--) {
        if (snapshot[i].depth === depth - 1) {
          keep.add(snapshot[i].uri);
          depth--;
        }
      }
    }
    return keep;
  };

  // -- folder search --------------------------------------------------------

  /**
   * @param {Document} fdoc - the folder tree's owner document
   */
  tk.ensure_search_style = (fdoc) => {
    if (fdoc.getElementById("tbkeys-search-style")) return;
    const style = fdoc.createElement("style");
    style.id = "tbkeys-search-style";
    style.textContent =
      ".tbkeys-search-match { background-color: #666666 !important; } " +
      ".tbkeys-search-active { background-color: #4D4528 !important; }";
    fdoc.head.appendChild(style);
  };

  /**
   * @param {Document} fdoc - the folder tree's owner document
   */
  tk.clear_search_highlights = (fdoc) => {
    fdoc
      .querySelectorAll(".tbkeys-search-match, .tbkeys-search-active")
      .forEach((el) =>
        el.classList.remove("tbkeys-search-match", "tbkeys-search-active"),
      );
  };

  /**
   * Steps the active folder search to the next/previous match; returns false when there is no active search so the caller can fall back to the built-in find command.
   * @param {number} direction - 1 for next, -1 for previous
   * @returns {boolean} true if a search step was taken
   */
  tk.folder_search_step = (direction) => {
    const focused = tk.get_focused_element();
    const matches = window.folderSearchMatches;
    if (focused?.id !== "folderTree" || !matches?.length) return false;
    const ft = tk.get_folder_tree();
    ft.getRowAtIndex(matches[window.folderSearchIndex])?.classList.remove(
      "tbkeys-search-active",
    );
    window.folderSearchIndex =
      (window.folderSearchIndex + direction + matches.length) % matches.length;
    const idx = matches[window.folderSearchIndex];
    ft.getRowAtIndex(idx)?.classList.add("tbkeys-search-active");
    ft.selectedIndex = idx;
    ft.scrollToIndex?.(idx);
    return true;
  };

  // -- viewport repositioning -----------------------------------------------

  /**
   * Scrolls the tree so the current row lands at the given viewport position, without touching selection or currentIndex.
   * @param {Element} tt - the thread tree
   * @param {"top"|"center"|"bottom"} position - target position within the viewport
   */
  tk.reposition_row = (tt, position) => {
    const row_height = tt?._rowElementClass?.ROW_HEIGHT;
    if (!tt || typeof tt.currentIndex !== "number" || tt.currentIndex < 0)
      return;
    if (!row_height || typeof tt.scrollTo !== "function") return;
    const visible_height = tt.clientHeight;
    const top_of_row = row_height * tt.currentIndex;
    let target;
    if (position === "top") target = top_of_row;
    else if (position === "bottom")
      target = top_of_row + row_height - visible_height;
    else target = top_of_row + row_height / 2 - visible_height / 2;
    tt.scrollTo({ top: target, behavior: "instant" });
  };

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

  window.tk = tk;

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

  window.tk_quickmove_goto = () => {
    const extension = window.ExtensionParent?.GlobalManager?.getExtension?.(
      "quickmove@mozilla.kewis.ch",
    );
    if (!extension) {
      window.alert(
        "Quick Folder Move not installed or disabled, check about:addons",
      );
      return;
    }
    extension.shortcuts?.onCommand?.("goto");
  };

  for (let i = 0; i <= 9; i++) {
    window[`tk_digit_${i}`] = tk.digit(i);
  }

  for (const letter of MARK_LETTERS) {
    window[`tk_mark_set_${letter}`] = () => tk.set_mark(letter);
    window[`tk_mark_jump_${letter}`] = () => tk.jump_to_mark(letter);
  }

  window.tk_toggle_visual = () => {
    const was_visual = window.vim === "visual";
    window.vim = was_visual ? "normal" : "visual";
    const tt = tk.get_thread_tree();
    if (!was_visual) {
      if (tt) {
        window.visualAnchor = tt.currentIndex;
        window.visualEnd = tt.currentIndex;
      }
    } else {
      window.visualAnchor = undefined;
      window.visualEnd = undefined;
    }
    tk.repaint_mode();
  };

  window.tk_escape = () => {
    const was_visual = window.vim === "visual";
    window.vim = "normal";
    window.count = 0;
    tk.repaint_mode();
    if (was_visual) {
      const tt = tk.get_thread_tree();
      const end =
        typeof window.visualEnd === "number"
          ? window.visualEnd
          : tt?.currentIndex;
      if (tt && typeof end === "number") tt._selectSingle(end);
    }
    window.visualAnchor = undefined;
    window.visualEnd = undefined;
    const fdoc = window.gTabmail?.currentAbout3Pane?.document;
    const had_search = !!(
      window.folderSearchMatches && window.folderSearchMatches.length
    );
    if (fdoc) tk.clear_search_highlights(fdoc);
    window.folderSearchMatches = undefined;
    window.folderSearchIndex = undefined;
    if (had_search) {
      const ft = tk.get_folder_tree();
      if (ft) {
        const sel_uri = ft.getRowAtIndex(ft.selectedIndex)?.uri;
        const snapshot = tk.snapshot_folder_rows(ft);
        const sel_idx = snapshot.findIndex((r) => r.uri === sel_uri);
        const keep = tk.keep_ancestors(
          snapshot,
          sel_idx !== -1 ? [sel_idx] : [],
        );
        tk.collapse_folder_tree(
          ft,
          (row) => keep.has(row.uri) || row.uri === sel_uri,
        );
      }
    }
  };

  window.tk_mark_all_read = () => {
    const tt = tk.get_thread_tree();
    const hdr = tk.get_current_hdr(tt);
    tk.toggle_read_state(hdr);
    window.goDoCommand("cmd_markAllRead");
  };
  window.tk_mark_read = () => {
    const tt = tk.get_thread_tree();
    const hdr = tk.get_current_hdr(tt);
    tk.toggle_read_state(hdr);
    const n = tk.peek_count();
    tk.reset_count();
    tk.repeat_command("cmd_markAsRead", n);
  };
  window.tk_mark_unread = () => {
    const tt = tk.get_thread_tree();
    const hdr = tk.get_current_hdr(tt);
    tk.toggle_read_state(hdr);
    const n = tk.peek_count();
    tk.reset_count();
    tk.repeat_command("cmd_markAsUnread", n);
  };
  window.tk_mark_flagged = () => {
    const tt = tk.get_thread_tree();
    const hdr = tk.get_current_hdr(tt);
    tk.toggle_read_state(hdr);
    const n = tk.peek_count();
    tk.reset_count();
    tk.repeat_command("cmd_markAsFlagged", n);
  };
  window.tk_delete = () => {
    const n = tk.peek_count();
    tk.reset_count();
    tk.repeat_command("cmd_delete", n);
  };
  window.tk_archive = () => {
    const n = tk.peek_count();
    tk.reset_count();
    tk.repeat_command("cmd_archive", n);
  };
  window.tk_mark_junk_toggle = () => {
    const tt = tk.get_thread_tree();
    const hdr = tk.get_current_hdr(tt);
    if (!hdr) return;
    const is_junk = hdr.getStringProperty("junkscore") === "100";
    tk.toggle_read_state(hdr);
    window.goDoCommand(is_junk ? "cmd_markAsNotJunk" : "cmd_markAsJunk");
  };
  window.tk_move_to_projects = () => {
    const tt = tk.get_thread_tree();
    if (!tt) return;
    const hdr = tk.get_current_hdr(tt);
    tk.toggle_read_state(hdr);
    const folder = tk.find_folder_by_name(PROJECTS_FOLDER);
    if (!folder) return;
    tt.view?.doCommandWithFolder?.(
      window.Ci.nsMsgViewCommandType.moveMessages,
      folder,
    );
  };

  window.tk_goto_inbox = () =>
    tk.display_folder("mailbox://nobody@smart%20mailboxes/Inbox");
  window.tk_goto_trash = () =>
    tk.display_folder("mailbox://nobody@smart%20mailboxes/Trash");
  window.tk_goto_drafts = () =>
    tk.display_folder("mailbox://nobody@smart%20mailboxes/Drafts");
  window.tk_goto_sent = () =>
    tk.display_folder("mailbox://nobody@smart%20mailboxes/Sent");
  window.tk_goto_projects = () =>
    tk.show_folder(tk.find_folder_by_name(PROJECTS_FOLDER));
  window.tk_goto_folder = () => {
    tk.reset_count();
    const name = window.prompt("Go to folder:");
    if (!name) return;
    const folder = tk.find_folder_by_name(name);
    if (!folder) {
      window.alert(`No folder matching "${name}"`);
      return;
    }
    tk.show_folder(folder);
  };

  window.tk_jump_back = () => {
    const n = tk.peek_count();
    tk.reset_count();
    for (let i = 0; i < n; i++) {
      const uri = tk.jump_back_stack.pop();
      if (!uri) return;
      tk.jump_to(uri, tk.jump_forward_stack);
    }
  };
  window.tk_jump_forward = () => {
    const n = tk.peek_count();
    tk.reset_count();
    for (let i = 0; i < n; i++) {
      const uri = tk.jump_forward_stack.pop();
      if (!uri) return;
      tk.jump_to(uri, tk.jump_back_stack);
    }
  };

  window.tk_collapse_all = () => {
    const e = tk.get_focused_element();
    if (!e) return;
    if (e.id === "threadTree") {
      window.goDoCommand("cmd_collapseAllThreads");
      return;
    }
    if (e.id === "folderTree") tk.collapse_folder_tree(e);
  };
  window.tk_expand_all = () => {
    const e = tk.get_focused_element();
    if (!e) return;
    if (e.id === "threadTree") {
      window.goDoCommand("cmd_expandAllThreads");
      return;
    }
    if (e.id === "folderTree") tk.expand_folder_tree(e);
  };

  window.tk_scroll_top = () => tk.reposition_row(tk.get_thread_tree(), "top");
  window.tk_scroll_center = () =>
    tk.reposition_row(tk.get_thread_tree(), "center");
  window.tk_scroll_bottom = () =>
    tk.reposition_row(tk.get_thread_tree(), "bottom");

  window.tk_folder_search = () => {
    const focused = tk.get_focused_element();
    if (focused?.id !== "folderTree") {
      window.goDoCommand("cmd_toggleQuickFilterBar");
      return;
    }
    const ft = tk.get_folder_tree();
    const term = window.prompt("Search folders:");
    if (!term) return;
    const t = term.toLowerCase();
    const fdoc = ft.ownerDocument;
    tk.ensure_search_style(fdoc);
    tk.clear_search_highlights(fdoc);
    tk.expand_folder_tree(ft);
    const snapshot = tk.snapshot_folder_rows(ft);
    const match_idxs = [];
    snapshot.forEach((r, i) => {
      if (r.name.toLowerCase().includes(t)) match_idxs.push(i);
    });
    const keep = tk.keep_ancestors(snapshot, match_idxs);
    tk.collapse_folder_tree(ft, (row) => keep.has(row.uri));
    const matches = [];
    for (let i = 0; i < ft.rowCount; i++) {
      const row = ft.getRowAtIndex(i);
      if (row?.nameLabel?.textContent?.toLowerCase().includes(t))
        matches.push(i);
    }
    matches.forEach((i) =>
      ft.getRowAtIndex(i)?.classList.add("tbkeys-search-match"),
    );
    window.folderSearchMatches = matches;
    window.folderSearchIndex = 0;
    if (matches.length) {
      ft.getRowAtIndex(matches[0])?.classList.add("tbkeys-search-active");
      ft.selectedIndex = matches[0];
      ft.scrollToIndex?.(matches[0]);
    }
  };

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

  window.tk_search_next = () => {
    if (!tk.folder_search_step(1)) window.goDoCommand("cmd_findAgain");
  };
  window.tk_search_prev = () => {
    if (!tk.folder_search_step(-1)) window.goDoCommand("cmd_findPrevious");
  };

  window.tk_motion_left = () => {
    const inbox = tk.get_inbox_doc();
    if (!inbox) return window.CloseTabOrWindow();
    const is_visual = tk.is_visual();
    const n = tk.peek_count();
    let e = inbox.activeElement;
    while (e) {
      if (e.id === "threadTree") {
        const v = e.view;
        let idx = e.currentIndex;
        if (v && !v.isContainer(idx)) {
          let parent = v.getParentIndex(idx);
          while (parent !== -1 && !v.isContainer(parent))
            parent = v.getParentIndex(parent);
          if (parent !== -1) {
            idx = parent;
            e._selectSingle(idx);
          }
        }
        if (v?.isContainer?.(idx) && v.isContainerOpen(idx))
          v.toggleOpenState(idx);
        break;
      }
      if (e.id === "folderTree") {
        for (let i = 0; i < n; i++)
          e.handleEvent(
            new window.KeyboardEvent("keydown", {
              key: "ArrowLeft",
              shiftKey: is_visual,
            }),
          );
        break;
      }
      e = e.parentElement;
    }
    tk.reset_count();
  };

  window.tk_motion_right = () => {
    const inbox = tk.get_inbox_doc();
    if (!inbox) return window.goDoCommand("cmd_open");
    const is_visual = tk.is_visual();
    const count = tk.peek_count();
    let e = inbox.activeElement;
    while (e) {
      if (e.id === "threadTree") {
        const idx = e.currentIndex;
        const v = e.view;
        if (v?.isContainer?.(idx) && !v.isContainerOpen(idx))
          v.toggleOpenState(idx);
        break;
      }
      if (e.id === "folderTree") {
        for (let i = 0; i < count; i++)
          e.handleEvent(
            new window.KeyboardEvent("keydown", {
              key: "ArrowRight",
              shiftKey: is_visual,
            }),
          );
        break;
      }
      e = e.parentElement;
    }
    tk.reset_count();
  };

  window.tk_motion_down = () => {
    const inbox = tk.get_inbox_doc();
    const message = tk.get_message_content_window();
    if (!inbox && !message) return;
    const is_visual = tk.is_visual();
    const count = tk.peek_count();
    if (message) return message.scrollByLines(3);
    let e = inbox.activeElement;
    while (e) {
      if (e.id === "threadTree") {
        if (is_visual) {
          const anchor =
            typeof window.visualAnchor === "number"
              ? window.visualAnchor
              : e.currentIndex;
          const cur =
            typeof window.visualEnd === "number"
              ? window.visualEnd
              : e.currentIndex;
          const last = (e.view?.rowCount ?? 1) - 1;
          const target = Math.min(cur + count, last);
          e._selectRange(anchor, target, false);
          window.visualEnd = target;
        } else {
          for (let i = 0; i < count; i++) window.goDoCommand("cmd_nextMsg");
        }
        break;
      }
      if (e.id === "folderTree") {
        for (let i = 0; i < count; i++)
          e.handleEvent(
            new window.KeyboardEvent("keydown", {
              key: "ArrowDown",
              shiftKey: is_visual,
            }),
          );
        break;
      }
      e = e.parentElement;
    }
    tk.reset_count();
  };

  window.tk_motion_up = () => {
    const inbox = tk.get_inbox_doc();
    const message = tk.get_message_content_window();
    if (!inbox && !message) return;
    const is_visual = tk.is_visual();
    const count = tk.peek_count();
    if (message) return message.scrollByLines(-3);
    let e = inbox.activeElement;
    while (e) {
      if (e.id === "threadTree") {
        if (is_visual) {
          const anchor =
            typeof window.visualAnchor === "number"
              ? window.visualAnchor
              : e.currentIndex;
          const cur =
            typeof window.visualEnd === "number"
              ? window.visualEnd
              : e.currentIndex;
          const target = Math.max(cur - count, 0);
          e._selectRange(anchor, target, false);
          window.visualEnd = target;
        } else {
          for (let i = 0; i < count; i++) window.goDoCommand("cmd_previousMsg");
        }
        break;
      }
      if (e.id === "folderTree") {
        for (let i = 0; i < count; i++)
          e.handleEvent(
            new window.KeyboardEvent("keydown", {
              key: "ArrowUp",
              shiftKey: is_visual,
            }),
          );
        break;
      }
      e = e.parentElement;
    }
    tk.reset_count();
  };

  window.tk_page_up = () => {
    const e = tk.get_focused_element();
    if (e)
      e.handleEvent(new window.KeyboardEvent("keydown", { key: "PageUp" }));
  };
  window.tk_page_down = () => {
    const e = tk.get_focused_element();
    if (e)
      e.handleEvent(new window.KeyboardEvent("keydown", { key: "PageDown" }));
  };

  window.tk_goto_top = () => {
    const is_visual = tk.is_visual();
    const e = tk.get_focused_element();
    if (!e) return;
    const n = tk.peek_count();
    if (e.id === "threadTree") {
      const last = (e.view?.rowCount ?? 1) - 1;
      const target = Math.min(Math.max(n - 1, 0), Math.max(last, 0));
      if (is_visual) {
        const anchor =
          typeof window.visualAnchor === "number"
            ? window.visualAnchor
            : e.currentIndex;
        e._selectRange(anchor, target, false);
        window.visualEnd = target;
      } else {
        e._selectSingle(target);
      }
    } else if (e.id === "folderTree") {
      e.handleEvent(
        new window.KeyboardEvent("keydown", {
          key: "Home",
          shiftKey: is_visual,
        }),
      );
    }
    tk.reset_count();
  };

  window.tk_goto_bottom = () => {
    const is_visual = tk.is_visual();
    const e = tk.get_focused_element();
    if (!e) return;
    const has_count = tk.has_count();
    const n = tk.peek_count();
    if (e.id === "threadTree") {
      const last = (e.view?.rowCount ?? 1) - 1;
      const target = has_count
        ? Math.min(Math.max(n - 1, 0), Math.max(last, 0))
        : last;
      if (is_visual) {
        const anchor =
          typeof window.visualAnchor === "number"
            ? window.visualAnchor
            : e.currentIndex;
        e._selectRange(anchor, target, false);
        window.visualEnd = target;
      } else {
        e._selectSingle(target);
      }
    } else if (e.id === "folderTree") {
      e.handleEvent(
        new window.KeyboardEvent("keydown", {
          key: "End",
          shiftKey: is_visual,
        }),
      );
    }
    tk.reset_count();
  };

  window.tk_repeat_last = () => {
    const last = tk.last_action;
    if (!last || typeof window[last.name] !== "function") {
      tk.reset_count();
      return;
    }
    if (!tk.has_count()) window.count = last.count;
    window[last.name]();
  };

  [
    "tk_delete",
    "tk_archive",
    "tk_mark_read",
    "tk_mark_unread",
    "tk_mark_flagged",
  ].forEach(tk.record_action);
  tk.repaint_mode();
})();
