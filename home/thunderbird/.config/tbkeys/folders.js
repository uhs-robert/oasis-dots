// Folder lookup/display, jump history, marks, folder-tree expand/collapse and
// goto commands. search.js reuses the tree-shaping helpers for accept/escape.
(function (tk) {
  "use strict";

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
      const raw = window.Services?.prefs?.getStringPref?.(tk.MARK_PREF, "{}");
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
    window.Services?.prefs?.setStringPref?.(tk.MARK_PREF, JSON.stringify(marks));
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

  // -- flat tk_* functions for keys.json "func:" bindings ------------------

  window.tk_goto_inbox = () =>
    tk.display_folder("mailbox://nobody@smart%20mailboxes/Inbox");
  window.tk_goto_trash = () =>
    tk.display_folder("mailbox://nobody@smart%20mailboxes/Trash");
  window.tk_goto_drafts = () =>
    tk.display_folder("mailbox://nobody@smart%20mailboxes/Drafts");
  window.tk_goto_sent = () =>
    tk.display_folder("mailbox://nobody@smart%20mailboxes/Sent");
  window.tk_goto_projects = () =>
    tk.show_folder(tk.find_folder_by_name(tk.PROJECTS_FOLDER));
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

  for (const letter of tk.MARK_LETTERS) {
    window[`tk_mark_set_${letter}`] = () => tk.set_mark(letter);
    window[`tk_mark_jump_${letter}`] = () => tk.jump_to_mark(letter);
  }
})(window.tk);
