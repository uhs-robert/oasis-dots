// Message mutations: read/unread/flag/junk/delete/archive/move, and
// repeat-last-action via tk.record_action / tk.last_action from core.js.
(function (tk) {
  "use strict";

  // -- flat tk_* functions for keys.json "func:" bindings ------------------

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
    const folder = tk.find_folder_by_name(tk.PROJECTS_FOLDER);
    if (!folder) return;
    tt.view?.doCommandWithFolder?.(
      window.Ci.nsMsgViewCommandType.moveMessages,
      folder,
    );
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
})(window.tk);
