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

  tk.command_aliases = {};

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

  // Shared with filter's complete(), so run and completion never drift apart.
  const FILTERS = {
    unread: () => window.goDoCommand("cmd_viewUnreadMsgs"),
    all: () => window.goDoCommand("cmd_viewAllMsgs"),
    starred: () => window.tk_toggle_starred_filter(),
  };

  // Shared with focus's complete(), so run and completion never drift apart.
  const PANES = {
    folder: () => window.tk_focus_folder_tree(),
    thread: () => window.tk_focus_thread_tree(),
    message: () => window.tk_focus_message_pane(),
  };

  // Folder names may contain spaces, so move/open treat everything after the
  // command name as one token rather than splitting args on whitespace.
  let folder_names = null;

  /**
   * Enumerating every account's descendants on each keystroke is the one
   * expensive completion source, so it is held for one command-line session.
   * @returns {string[]} every folder name, cached until the bar closes
   */
  const complete_folder_names = () => {
    folder_names ??= tk.all_folders().map((f) => f.name);
    return folder_names;
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
    delete: {
      usage: "delete",
      description: "Delete the current message or visual selection",
      run: ({ args }) => {
        if (args.length) return tk.commands.delete.usage;
        window.tk_delete();
      },
    },
    focus: {
      usage: "focus <folder|thread|message>",
      description: "Move focus to a pane",
      complete: () => Object.keys(PANES),
      run: ({ args }) => {
        if (!args.length) return tk.commands.focus.usage;
        const fn = Object.hasOwn(PANES, args[0]) ? PANES[args[0]] : null;
        if (!fn)
          return `Unknown pane "${args[0]}" (valid: ${Object.keys(PANES).join(", ")})`;
        fn();
      },
    },
    move: {
      usage: "move <folder>",
      description: "Move the current message or visual selection to a folder",
      complete_rest: true,
      complete: () => complete_folder_names(),
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
      complete: () => Object.keys(FILTERS),
      run: ({ args }) => {
        if (!args.length) return tk.commands.filter.usage;
        const fn = Object.hasOwn(FILTERS, args[0]) ? FILTERS[args[0]] : null;
        if (!fn)
          return `Unknown filter "${args[0]}" (valid: ${Object.keys(FILTERS).join(", ")})`;
        fn();
      },
    },
    open: {
      usage: "open <folder>",
      description: "Open a folder by name",
      complete_rest: true,
      complete: () => complete_folder_names(),
      run: ({ args }) => {
        const name = args.join(" ");
        if (!name) return tk.commands.open.usage;
        const folder = tk.find_folder_by_name(name);
        if (!folder) return `No folder matching "${name}"`;
        tk.show_folder(folder);
      },
    },
    help: {
      usage: "help [command]",
      description: "List commands, or show one command in detail",
      complete: () => [
        ...Object.keys(tk.commands),
        ...Object.keys(tk.command_aliases),
      ],
      run: ({ args }) => {
        if (!args.length) {
          render_command_help();
          return;
        }
        const typed = args[0].toLowerCase();
        const cmd = tk.resolve_command(typed);
        if (!cmd) return `Unknown command ":${typed}"`;
        const canonical = Object.hasOwn(tk.command_aliases, typed)
          ? tk.command_aliases[typed]
          : typed;
        render_command_help(canonical);
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

  // -- completion ---------------------------------------------------------

  /**
   * Orders candidates prefix matches first, then substring matches, each
   * group alphabetical, de-duplicated.
   * @param {string[]} names - candidate strings
   * @param {string} prefix - raw text being completed, matched case-insensitively
   * @returns {string[]} ordered, de-duplicated candidates
   */
  tk.filter_candidates = (names, prefix) => {
    const target = prefix.toLowerCase();
    const unique = [...new Set(names)];
    const starts = unique
      .filter((n) => n.toLowerCase().startsWith(target))
      .sort();
    const contains = unique
      .filter(
        (n) =>
          !n.toLowerCase().startsWith(target) &&
          n.toLowerCase().includes(target),
      )
      .sort();
    return [...starts, ...contains];
  };

  /**
   * Decides, from the raw (untrimmed) command-line value, what is being
   * completed: command/alias names when there is no whitespace yet,
   * otherwise a resolved command's own complete() candidates.
   * @param {string} value - raw command-line input
   * @returns {{token_start: number, candidates: string[]}} completion state, or null when nothing can be completed
   */
  tk.compute_completion = (value) => {
    if (!/\s/.test(value)) {
      const names = [
        ...Object.keys(tk.commands),
        ...Object.keys(tk.command_aliases),
      ];
      return { token_start: 0, candidates: tk.filter_candidates(names, value) };
    }
    const space_idx = value.search(/\s/);
    const cmd_name = value.slice(0, space_idx).toLowerCase();
    const cmd = tk.resolve_command(cmd_name);
    if (!cmd || typeof cmd.complete !== "function") return null;
    const lead = value.slice(space_idx).match(/^\s*/)[0].length;
    const rest_start = space_idx + lead;
    const rest = value.slice(rest_start);
    let token_start, prefix;
    if (cmd.complete_rest) {
      token_start = rest_start;
      prefix = rest;
    } else {
      const m = rest.match(/\S*$/);
      token_start = rest_start + m.index;
      prefix = m[0];
    }
    const { args } = tk.parse_command(value);
    const candidates = tk.filter_candidates(
      cmd.complete({ args, prefix }) ?? [],
      prefix,
    );
    return { token_start, candidates };
  };

  // -- help panel ---------------------------------------------------------

  /**
   * @returns {Element} the injected :help panel, creating it if absent
   */
  const ensure_command_help_panel = () => {
    const doc = window.document;
    let el = doc.getElementById("tbkeys-command-help");
    if (el) return el;
    el = doc.createElement("div");
    el.id = "tbkeys-command-help";
    el.style.cssText =
      "position:fixed; right:12px; bottom:32px; z-index:2147483647; " +
      `background:${tk.whichkey_colors.bg}; border:1px solid #333; ` +
      "font:12px monospace; padding:6px 10px; pointer-events:none;";
    (doc.body ?? doc.documentElement).appendChild(el);
    return el;
  };

  /**
   * @param {Document} doc - owner document to create the row in
   * @param {string} key - command name, canonical
   * @returns {Element} one command's help row: names in the key color, usage/description in the label color
   */
  const command_help_row = (doc, key) => {
    const cmd = tk.commands[key];
    const aliases = Object.entries(tk.command_aliases)
      .filter(([, target]) => target === key)
      .map(([alias]) => alias);
    const names = [key, ...aliases].join(", ");
    return tk.whichkey_entry_row(
      doc,
      names,
      `${cmd.usage} -- ${cmd.description}`,
      tk.whichkey_colors.label,
    );
  };

  let command_help_dismiss = null;

  /**
   * Installs the capture-phase keydown listener that removes the :help panel
   * on the next key press; a no-op while one is already installed.
   */
  const install_command_help_dismiss = () => {
    if (command_help_dismiss) return;
    command_help_dismiss = () => remove_command_help();
    window.addEventListener("keydown", command_help_dismiss, {
      capture: true,
    });
  };

  /**
   * Removes the :help panel and its dismiss listener, if present.
   */
  const remove_command_help = () => {
    if (command_help_dismiss) {
      window.removeEventListener("keydown", command_help_dismiss, {
        capture: true,
      });
      command_help_dismiss = null;
    }
    window.document.getElementById("tbkeys-command-help")?.remove();
  };

  /**
   * Renders the :help panel: every command sorted by name, or just `name`.
   * @param {string} [name] - canonical command name to show alone
   */
  const render_command_help = (name) => {
    const panel = ensure_command_help_panel();
    const doc = panel.ownerDocument;
    panel.textContent = "";
    if (name) {
      panel.appendChild(
        tk.whichkey_text_row(
          doc,
          `:help -- ${name} --`,
          tk.whichkey_colors.header,
        ),
      );
      panel.appendChild(command_help_row(doc, name));
    } else {
      panel.appendChild(
        tk.whichkey_text_row(
          doc,
          ":help -- commands --",
          tk.whichkey_colors.header,
        ),
      );
      for (const key of Object.keys(tk.commands).sort())
        panel.appendChild(command_help_row(doc, key));
    }
    panel.style.display = "block";
    install_command_help_dismiss();
  };

  // -- input UI ---------------------------------------------------------------

  tk.command_mode_prior = null;
  tk.command_completion = null;

  /**
   * @returns {Element} the injected command bar, creating it (with its menu and input) if absent
   */
  tk.ensure_command_bar = () => {
    const doc = window.document;
    let bar = doc.getElementById("tbkeys-command-bar");
    if (bar) return bar;
    bar = doc.createElement("div");
    bar.id = "tbkeys-command-bar";
    bar.style.cssText =
      "position:fixed; left:0; right:0; bottom:0; z-index:2147483647; " +
      "display:flex; flex-direction:column; align-items:stretch; " +
      `background:${tk.whichkey_colors.bg}; border-top:1px solid #333; ` +
      "font:12px monospace; color:#fff;";

    const menu = doc.createElement("div");
    menu.id = "tbkeys-command-menu";
    menu.style.cssText = "display:none; pointer-events:none; padding:2px 8px;";

    const row = doc.createElement("div");
    row.style.cssText =
      "display:flex; align-items:center; gap:4px; padding:4px 8px;";
    const label = doc.createElement("span");
    label.textContent = ":";
    const input = doc.createElement("input");
    input.id = "tbkeys-command-input";
    input.type = "text";
    input.setAttribute("aria-label", "tbkeys command");
    input.style.cssText =
      "flex:1; font:inherit; background:#222; color:#fff; " +
      "border:1px solid #666; padding:2px 4px;";
    row.appendChild(label);
    row.appendChild(input);

    bar.appendChild(menu);
    bar.appendChild(row);
    (doc.body ?? doc.documentElement).appendChild(bar);
    return bar;
  };

  tk.close_command_bar = () => {
    tk.command_completion = null;
    folder_names = null;
    window.document.getElementById("tbkeys-command-bar")?.remove();
  };

  /**
   * Repaints the completion menu from tk.command_completion; hidden when
   * there is no candidate to show.
   */
  tk.render_command_menu = () => {
    const menu = window.document.getElementById("tbkeys-command-menu");
    if (!menu) return;
    const state = tk.command_completion;
    menu.textContent = "";
    if (!state || !state.candidates.length) {
      menu.style.display = "none";
      return;
    }
    const doc = menu.ownerDocument;
    const colors = tk.whichkey_colors;
    state.candidates.forEach((candidate, i) => {
      const row = doc.createElement("div");
      row.textContent = candidate;
      if (i === state.index) {
        row.style.background = colors.key;
        row.style.color = colors.bg;
      } else {
        row.style.color = colors.label;
      }
      menu.appendChild(row);
    });
    menu.style.display = "block";
  };

  /**
   * @param {number} dir - +1 to cycle forward, -1 to cycle backward
   */
  tk.cycle_completion = (dir) => {
    const input = window.document.getElementById("tbkeys-command-input");
    if (!input) return;
    if (!tk.command_completion) {
      const computed = tk.compute_completion(input.value);
      if (!computed || !computed.candidates.length) return;
      tk.command_completion = { ...computed, index: -1 };
    }
    const state = tk.command_completion;
    const n = state.candidates.length;
    state.index =
      state.index === -1
        ? dir > 0
          ? 0
          : n - 1
        : (((state.index + dir) % n) + n) % n;
    const candidate = state.candidates[state.index];
    // Deliberately not recomputed from the written value: the candidate list
    // must stay put across cycles, or completing one entry strands the rest.
    const new_value = input.value.slice(0, state.token_start) + candidate;
    input.value = new_value;
    input.setSelectionRange(new_value.length, new_value.length);
    tk.render_command_menu();
  };

  /**
   * Recomputes the menu from `value` with nothing highlighted; an empty value
   * lists every command, so ":" opens onto the full set.
   * @param {string} value - raw command-line input
   */
  tk.refresh_completion = (value) => {
    const computed = tk.compute_completion(value);
    tk.command_completion =
      computed && computed.candidates.length
        ? { ...computed, index: -1 }
        : null;
    tk.render_command_menu();
  };

  /**
   * @param {InputEvent} e
   */
  tk.command_input_input = (e) => {
    tk.refresh_completion(e.target.value);
  };

  /**
   * @param {KeyboardEvent} e
   */
  tk.command_input_keydown = (e) => {
    if (e.key === "Tab") {
      e.preventDefault();
      tk.cycle_completion(e.shiftKey ? -1 : 1);
    } else if (e.key === "Enter") {
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
    remove_command_help();
  };

  // -- flat tk_* functions for keys.json "func:" bindings ------------------

  window.tk_command_line = () => {
    tk.reset_count();
    tk.command_mode_prior = window.vim ?? "normal";
    tk.ensure_command_bar();
    const input = window.document.getElementById("tbkeys-command-input");
    input.value = "";
    tk.refresh_completion("");
    input.onkeydown = tk.command_input_keydown;
    input.oninput = tk.command_input_input;
    input.onfocusout = tk.command_input_focusout;
    input.focus();
  };
})(window.tk);
