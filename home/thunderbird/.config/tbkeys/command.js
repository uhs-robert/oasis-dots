// Vim-style ":" command line: input UI -> parser -> command registry ->
// existing helper APIs. tk_command_line opens it; Enter/Escape close it.
(function (tk) {
  "use strict";

  // -- parser ---------------------------------------------------------------

  /**
   * Splits a command line into a lowercased name and whitespace-split args, with support for double-quoted segments.
   * @param {string} text - raw command-line input, without the leading ":"
   * @returns {{name: string, args: string[]}}
   */
  tk.parse_command = (text) => {
    const trimmed = (text ?? "").trim();
    if (!trimmed) return { name: "", args: [] };
    const space_idx = trimmed.search(/\s/);
    const name = (
      space_idx === -1 ? trimmed : trimmed.slice(0, space_idx)
    ).toLowerCase();
    const rest = space_idx === -1 ? "" : trimmed.slice(space_idx + 1).trim();
    const args = [];
    const re = /"([^"]*)"|(\S+)/g;
    let m;
    while ((m = re.exec(rest))) args.push(m[1] ?? m[2]);
    return { name, args };
  };

  // -- command registry -------------------------------------------------------

  tk.command_aliases = { a: "archive", mv: "move", e: "open" };

  /**
   * @param {string} name - command name or alias, already lowercased
   * @returns {Object} the matching command definition, or undefined
   */
  tk.resolve_command = (name) => {
    const key = Object.hasOwn(tk.command_aliases, name)
      ? tk.command_aliases[name]
      : name;
    return Object.hasOwn(tk.commands, key) ? tk.commands[key] : undefined;
  };

  tk.commands = {
    archive: {
      usage: "archive",
      description: "Archive the current message or visual selection",
      run: ({ args }) => {
        if (args.length) return tk.commands.archive.usage;
        window.tk_archive();
      },
    },
    move: {
      usage: "move <folder>",
      description: "Move the current message or visual selection to a folder",
      run: ({ args }) => {
        const name = args.join(" ");
        if (!name) return tk.commands.move.usage;
        const folder = tk.find_folder_by_name(name);
        if (!folder) return `No folder matching "${name}"`;
        tk.move_to_folder(folder)();
      },
    },
    filter: {
      usage: "filter <unread|all|starred>",
      description: "Apply a message view filter",
      run: ({ args }) => {
        const filters = {
          unread: () => window.goDoCommand("cmd_viewUnreadMsgs"),
          all: () => window.goDoCommand("cmd_viewAllMsgs"),
          starred: () => window.tk_toggle_starred_filter(),
        };
        if (!args.length) return tk.commands.filter.usage;
        const fn = filters[args[0]];
        if (!fn)
          return `Unknown filter "${args[0]}" (valid: ${Object.keys(filters).join(", ")})`;
        fn();
      },
    },
    open: {
      usage: "open <folder>",
      description: "Open a folder by name",
      run: ({ args }) => {
        const name = args.join(" ");
        if (!name) return tk.commands.open.usage;
        const folder = tk.find_folder_by_name(name);
        if (!folder) return `No folder matching "${name}"`;
        tk.show_folder(folder);
      },
    },
  };

  /**
   * Parses and runs a full command-line string, reporting an unknown command
   * or a handler's returned error string via window.alert.
   * @param {string} text - raw command-line input, without the leading ":"
   */
  tk.execute_command_text = (text) => {
    const { name, args } = tk.parse_command(text);
    if (!name) return;
    const cmd = tk.resolve_command(name);
    if (!cmd) {
      window.alert(`Unknown command ":${name}"`);
      return;
    }
    const error = cmd.run({ args });
    if (error) window.alert(error);
  };

  // -- input UI ---------------------------------------------------------------

  tk.command_mode_prior = null;

  /**
   * @returns {Element} the injected command bar, creating it (with its input) if absent
   */
  tk.ensure_command_bar = () => {
    const doc = window.document;
    let bar = doc.getElementById("tbkeys-command-bar");
    if (bar) return bar;
    bar = doc.createElement("div");
    bar.id = "tbkeys-command-bar";
    bar.style.cssText =
      "position:fixed; left:0; right:0; bottom:0; z-index:2147483647; " +
      "display:flex; align-items:center; gap:4px; " +
      "background:#0C0E13; border-top:1px solid #333; " +
      "font:12px monospace; padding:4px 8px; color:#fff;";
    const label = doc.createElement("span");
    label.textContent = ":";
    const input = doc.createElement("input");
    input.id = "tbkeys-command-input";
    input.type = "text";
    input.setAttribute("aria-label", "tbkeys command");
    input.style.cssText =
      "flex:1; font:inherit; background:#222; color:#fff; " +
      "border:1px solid #666; padding:2px 4px;";
    bar.appendChild(label);
    bar.appendChild(input);
    (doc.body ?? doc.documentElement).appendChild(bar);
    return bar;
  };

  tk.close_command_bar = () => {
    window.document.getElementById("tbkeys-command-bar")?.remove();
  };

  /**
   * @param {KeyboardEvent} e
   */
  tk.command_input_keydown = (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      tk.finish_command_line(true, e.target.value);
    } else if (e.key === "Escape") {
      e.preventDefault();
      tk.finish_command_line(false, "");
    }
  };

  /**
   * Closes the command line, restoring the vim mode that was active when ":"
   * was pressed before anything else runs, since focusing the input forced
   * insert mode and a handler acting on a visual range must see it restored.
   * @param {boolean} execute - true to parse and run `text`, false to just cancel
   * @param {string} text - raw command-line input, without the leading ":"
   */
  tk.finish_command_line = (execute, text) => {
    if (!window.document.getElementById("tbkeys-command-bar")) return;
    const prior = tk.command_mode_prior ?? "normal";
    tk.command_mode_prior = null;
    window.vim = prior;
    tk.mode_before_insert = null;
    tk.close_command_bar();
    window.tk_focus_thread_tree();
    tk.sync_insert_mode();
    tk.repaint_mode();
    if (execute) tk.execute_command_text(text);
  };

  /**
   * @param {FocusEvent} e
   */
  tk.command_input_focusout = (e) => {
    // relatedTarget is null when the whole window deactivates, which should
    // leave a half-typed command alone rather than cancelling it.
    if (e.relatedTarget) tk.finish_command_line(false, "");
  };

  tk.command_teardown = () => {
    if (window.document.getElementById("tbkeys-command-bar"))
      window.vim = tk.command_mode_prior ?? "normal";
    tk.close_command_bar();
  };

  // -- flat tk_* functions for keys.json "func:" bindings ------------------

  window.tk_command_line = () => {
    tk.reset_count();
    tk.command_mode_prior = window.vim ?? "normal";
    tk.ensure_command_bar();
    const input = window.document.getElementById("tbkeys-command-input");
    input.value = "";
    input.onkeydown = tk.command_input_keydown;
    input.onfocusout = tk.command_input_focusout;
    input.focus();
  };
})(window.tk);
