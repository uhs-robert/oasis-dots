// Message mutations: read/unread/flag/junk/delete/archive/move, and
// repeat-last-action via tk.record_action / tk.last_action from core.js.
(function (tk) {
  "use strict";

  // -- flat tk_* functions for keys.json "func:" bindings ------------------

  // Repetition is opt-in: a count only means anything where the acted-on row
  // leaves the view. Every chord consumes the count either way.
  const m_chord =
    (apply, { restore = true, repeat = false } = {}) =>
    () => {
      const tt = tk.get_thread_tree();
      const range = tk.resolve_action_range(tt);
      if (restore) tk.restore_read_state();
      else tk.read_snapshot = null;
      const times = repeat ? range.count : 1;
      tk.effective_count = times;
      let cursor;
      for (let i = 0; i < times; i++) cursor = apply(tt, range);
      if (range.is_visual)
        tk.finish_visual_action(tt, cursor ?? range.cursor_index);
    };

  const act_over_range = (cmd) => () => {
    const tt = tk.get_thread_tree();
    const range = tk.resolve_action_range(tt);
    if (range.is_visual) {
      window.goDoCommand(cmd);
      tk.finish_visual_action(tt, range.top_index);
      return;
    }
    tk.repeat_command(cmd, range.count);
  };

  window.tk_mark_all_read = m_chord(() =>
    window.goDoCommand("cmd_markAllRead"),
  );
  window.tk_mark_read = m_chord(
    (tt) => tk.run_view_command(tt, "markMessagesRead"),
    {
      restore: false,
      repeat: true,
    },
  );
  window.tk_mark_unread = m_chord(
    (tt) => tk.run_view_command(tt, "markMessagesUnread"),
    { restore: false, repeat: true },
  );
  window.tk_mark_flagged = m_chord((tt, range) =>
    tk.run_view_command(
      tt,
      range.anchor_hdr?.isFlagged ? "unflagMessages" : "flagMessages",
    ),
  );
  window.tk_mark_junk_toggle = m_chord((tt, range) => {
    if (!range.anchor_hdr) return;
    const is_junk = range.anchor_hdr.getStringProperty("junkscore") === "100";
    tk.run_view_command(tt, is_junk ? "unjunk" : "junk");
  });
  window.tk_move_to_projects = m_chord((tt, range) => {
    const folder = tk.find_folder_by_name(tk.PROJECTS_FOLDER);
    if (!folder) return;
    tt?.view?.doCommandWithFolder?.(
      window.Ci.nsMsgViewCommandType.moveMessages,
      folder,
    );
    return range.top_index;
  });

  window.tk_delete = act_over_range("cmd_delete");
  window.tk_archive = act_over_range("cmd_archive");

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
