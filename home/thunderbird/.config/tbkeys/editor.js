// External compose editing through a real Neovim process. Plain-text compose
// uses plain text; HTML compose uses Markdown and is converted back through
// Thunderbird's HTML editor API after the external edit completes.
(function (tk) {
  "use strict";

  const SESSION_KEY = "__tbkeys_compose_editor_session";
  const EDITOR_COMMAND_KEY = "__tbkeys_external_editor_command";
  const MARKDOWN_COMMAND_KEY = "__tbkeys_markdown_converter_command";
  const DEFAULT_COMMAND = ["kitty", "--wait", "nvim"];
  const DEFAULT_MARKDOWN_COMMAND = ["pandoc"];
  const Cc = () =>
    window.Cc ??
    window.Components?.classes ??
    (typeof Components !== "undefined" ? Components.classes : null);
  const Ci = () =>
    window.Ci ??
    window.Components?.interfaces ??
    (typeof Components !== "undefined" ? Components.interfaces : null);

  const report = (message) => tk.show_status?.(`EDITOR: ${message}`);

  const compose_editor = () =>
    typeof window.GetCurrentEditor === "function"
      ? window.GetCurrentEditor()
      : null;

  const is_compose_window = () =>
    window.document?.documentElement?.getAttribute("windowtype") === "msgcompose";

  const is_compose_body_focus = () => {
    if (!is_compose_window()) return false;
    const editor = compose_editor();
    const body = editor?.document?.body;
    const inner_active = editor?.document?.activeElement;
    if (body && (inner_active === body || body.contains(inner_active))) return true;
    const outer_active = window.document?.activeElement;
    return ["content-frame", "messageEditor"].some(
      (id) => outer_active?.id === id,
    );
  };
  tk.is_compose_body_focus = is_compose_body_focus;

  const body_source = (editor) => {
    const interfaces = Ci();
    const encoder = interfaces?.nsIDocumentEncoder;
    const flags =
      (encoder?.OutputLFLineBreak ?? 0) |
      (encoder?.OutputBodyOnly ?? 0) |
      (encoder?.OutputNoScriptContent ?? 0);
    const html = !!window.gMsgCompose?.composeHTML;
    return {
      html,
      value: editor.outputToString(html ? "text/html" : "text/plain", flags),
    };
  };

  const tmp_file = () => {
    const classes = Cc();
    const interfaces = Ci();
    if (!classes || !interfaces) throw new Error("XPCOM services unavailable");
    const dir = Services.dirsvc.get("TmpD", interfaces.nsIFile).clone();
    dir.append("tbkeys-compose");
    if (!dir.exists()) dir.create(interfaces.nsIFile.DIRECTORY_TYPE, 0o700);
    const file = dir.clone();
    file.append("compose.txt");
    file.createUnique(interfaces.nsIFile.NORMAL_FILE_TYPE, 0o600);
    return file;
  };

  const write_utf8 = (file, text) => {
    const classes = Cc();
    const interfaces = Ci();
    const stream = classes["@mozilla.org/network/file-output-stream;1"].createInstance(
      interfaces.nsIFileOutputStream,
    );
    const converter = classes[
      "@mozilla.org/intl/converter-output-stream;1"
    ].createInstance(interfaces.nsIConverterOutputStream);
    stream.init(file, 0x02 | 0x08 | 0x20, 0o600, 0);
    converter.init(stream, "UTF-8", 0, 0);
    converter.writeString(text);
    converter.close();
  };

  const read_utf8 = (file) => {
    const classes = Cc();
    const interfaces = Ci();
    const stream = classes["@mozilla.org/network/file-input-stream;1"].createInstance(
      interfaces.nsIFileInputStream,
    );
    const converter = classes[
      "@mozilla.org/intl/converter-input-stream;1"
    ].createInstance(interfaces.nsIConverterInputStream);
    stream.init(file, 0x01, 0, 0);
    converter.init(stream, "UTF-8", 4096, 0xFFFD);
    let result = "";
    const buffer = {};
    while (converter.readString(4096, buffer)) result += buffer.value;
    converter.close();
    return result;
  };

  const executable_for = (name) => {
    const interfaces = Ci();
    const file = Cc()["@mozilla.org/file/local;1"].createInstance(
      interfaces.nsIFile,
    );
    if (name.startsWith("/")) {
      file.initWithPath(name);
      return file.exists() && file.isExecutable() ? file : null;
    }
    const path = Services.env.get("PATH") ?? "";
    for (const directory of path.split(":")) {
      if (!directory) continue;
      file.initWithPath(`${directory}/${name}`);
      if (file.exists() && file.isExecutable()) return file;
    }
    return null;
  };

  const launch_process = (command_key, default_command, args, on_exit) => {
    const command = window[command_key] ?? default_command;
    if (!Array.isArray(command) || !command.length)
      throw new Error(`${command_key} must be a non-empty array`);
    const executable = executable_for(command[0]);
    if (!executable) throw new Error(`cannot find ${command[0]}`);
    const process = Cc()["@mozilla.org/process/util;1"].createInstance(
      Ci().nsIProcess,
    );
    process.init(executable);
    const process_args = [...command.slice(1), ...args];
    process.runAsync(process_args, process_args.length, {
      observe(subject, topic) {
        if (topic === "process-finished" || topic === "process-failed")
          on_exit(topic === "process-finished" && subject.exitValue === 0);
      },
    });
    return process;
  };

  const launch_editor = (file, on_exit, markdown = false) =>
    launch_process(
      EDITOR_COMMAND_KEY,
      DEFAULT_COMMAND,
      markdown ? ["-c", "setlocal filetype=markdown", file.path] : [file.path],
      on_exit,
    );

  const launch_markdown = (input, output, on_exit) =>
    launch_process(
      MARKDOWN_COMMAND_KEY,
      DEFAULT_MARKDOWN_COMMAND,
      ["--from=gfm", "--to=html5", "--wrap=none", "--output", output.path, input.path],
      on_exit,
    );

  const launch_html_to_markdown = (input, output, on_exit) =>
    launch_process(
      MARKDOWN_COMMAND_KEY,
      DEFAULT_MARKDOWN_COMMAND,
      ["--from=html", "--to=gfm", "--wrap=none", "--output", output.path, input.path],
      on_exit,
    );

  const cleanup = (session) => {
    try {
      if (session.file?.exists()) session.file.remove(false);
      if (session.source_file?.exists()) session.source_file.remove(false);
      if (session.html_file?.exists()) session.html_file.remove(false);
    } catch (_) {
      // Best effort cleanup; the unique file remains safe to remove later.
    }
    if (window[SESSION_KEY] === session) window[SESSION_KEY] = null;
  };

  const apply_body = (editor, snapshot, value) => {
    if (snapshot.html) {
      const interfaces = Ci();
      let html_editor = editor;
      if (
        typeof html_editor.insertHTML !== "function" &&
        interfaces?.nsIHTMLEditor
      )
        html_editor = editor.QueryInterface(interfaces.nsIHTMLEditor);
      if (typeof html_editor.insertHTML !== "function")
        throw new Error("Thunderbird HTML editor API is unavailable");
      html_editor.beginTransaction?.();
      try {
        html_editor.selectAll();
        html_editor.insertHTML(value);
      } finally {
        html_editor.endTransaction?.();
      }
    } else {
      editor.beginTransaction?.();
      try {
        editor.selectAll();
        editor.insertText(value);
      } finally {
        editor.endTransaction?.();
      }
    }
    window.gMsgCompose.bodyModified = true;
    editor.document?.body?.focus?.();
  };

  tk.edit_compose_external = () => {
    if (!is_compose_window()) {
      report("only available in a compose window");
      return;
    }
    if (window[SESSION_KEY]) {
      report("an editor session is already active");
      return;
    }
    const editor = compose_editor();
    if (!editor) return report("compose editor is not ready");

    let original;
    let file;
    let source_file;
    let html_file;
    try {
      original = body_source(editor);
      file = tmp_file();
      if (original.html) {
        source_file = tmp_file();
        html_file = tmp_file();
        write_utf8(source_file, original.value);
      } else {
        write_utf8(file, original.value);
      }
    } catch (error) {
      for (const candidate of [file, source_file, html_file])
        try {
          if (candidate?.exists()) candidate.remove(false);
        } catch (_) {}
      report(`could not prepare temp file (${error})`);
      return;
    }

    const session = {
      editor,
      original,
      file,
      source_file,
      html_file,
      process: null,
    };
    window[SESSION_KEY] = session;

    const begin_editor = () => {
      if (original.html) session.markdown_original = read_utf8(file);
      session.process = launch_editor(file, (saved) => {
        try {
          if (!saved) {
            report("cancelled; body unchanged");
            cleanup(session);
            return;
          }
          const current = body_source(editor);
          if (current.html !== original.html || current.value !== original.value) {
            report("body changed in Betterbird; result not applied");
            cleanup(session);
            return;
          }
          if (original.html) {
            try {
              session.process = launch_markdown(file, html_file, (converted) => {
                try {
                  if (!converted)
                    return report("Markdown conversion failed; body unchanged");
                  const latest = body_source(editor);
                  if (latest.value !== original.value)
                    return report("body changed in Betterbird; result not applied");
                  const markdown = read_utf8(file);
                  const edited = read_utf8(html_file);
                  if (markdown !== session.markdown_original)
                    apply_body(editor, original, edited);
                  report(
                    markdown === session.markdown_original
                      ? "no changes"
                      : "updated HTML compose body",
                  );
                } finally {
                  cleanup(session);
                }
              });
            } catch (error) {
              cleanup(session);
              report(`could not convert Markdown (${error})`);
            }
            return;
          }
          const edited = read_utf8(file);
          if (edited !== original.value) apply_body(editor, original, edited);
          report(edited === original.value ? "no changes" : "updated compose body");
        } catch (error) {
          cleanup(session);
          report(`could not apply result (${error})`);
        } finally {
          if (!original.html) cleanup(session);
        }
      }, original.html);
    };

    try {
      session.process = original.html
        ? launch_html_to_markdown(source_file, file, (converted) => {
            if (!converted) {
              cleanup(session);
              report("HTML-to-Markdown conversion failed; body unchanged");
              return;
            }
            try {
              begin_editor();
            } catch (error) {
              cleanup(session);
              report(`could not launch Neovim (${error})`);
            }
          })
        : begin_editor();
    } catch (error) {
      cleanup(session);
      report(`could not launch editor (${error})`);
    }
  };

  const repaint_compose_mode = () => tk.repaint_mode?.();
  const compose_focus_handler = () =>
    window.setTimeout(() => {
      attach_editor_window();
      if (is_compose_body_focus()) {
        if (!window.__tbkeys_one_command_normal) window.vim = "insert";
      } else if (window.vim === "insert") {
        window.vim = "normal";
      }
      repaint_compose_mode();
    }, 0);

  const return_to_insert = () => {
    if (!window.__tbkeys_one_command_normal) return;
    window.setTimeout(() => {
      window.__tbkeys_one_command_normal = false;
      if (is_compose_body_focus()) window.vim = "insert";
      repaint_compose_mode();
    }, 0);
  };

  const compose_keydown_handler = (event) => {
    if (!is_compose_body_focus()) return;
    const key = event.key.toLowerCase();
    if (
      key === "e" &&
      event.ctrlKey &&
      !event.altKey &&
      !event.shiftKey &&
      !event.metaKey
    ) {
      event.preventDefault();
      event.stopImmediatePropagation();
      tk.edit_compose_external();
      return;
    }
    if (
      key === "o" &&
      event.ctrlKey &&
      !event.altKey &&
      !event.shiftKey &&
      !event.metaKey
    ) {
      event.preventDefault();
      event.stopImmediatePropagation();
      window.vim = "normal";
      window.__tbkeys_one_command_normal = true;
      repaint_compose_mode();
      return;
    }
    if (
      window.vim === "normal" &&
      key === "e" &&
      !event.ctrlKey &&
      !event.altKey &&
      !event.shiftKey &&
      !event.metaKey
    ) {
      event.preventDefault();
      event.stopPropagation();
      tk.edit_compose_external();
      return_to_insert();
      return;
    }
    if (
      window.__tbkeys_one_command_normal &&
      !["Control", "Alt", "Shift", "Meta"].includes(event.key)
    ) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return_to_insert();
    }
  };

  let inner_editor_window = null;
  const attach_editor_window = () => {
    const next = compose_editor()?.document?.defaultView;
    if (next === inner_editor_window) return;
    if (inner_editor_window) {
      inner_editor_window.removeEventListener("focusin", compose_focus_handler, true);
      inner_editor_window.removeEventListener("focusout", compose_focus_handler, true);
      inner_editor_window.removeEventListener("keydown", compose_keydown_handler, true);
    }
    inner_editor_window = next && next !== window ? next : null;
    if (!inner_editor_window) return;
    inner_editor_window.addEventListener("focusin", compose_focus_handler, true);
    inner_editor_window.addEventListener("focusout", compose_focus_handler, true);
    inner_editor_window.addEventListener("keydown", compose_keydown_handler, true);
  };

  window.tk_edit_compose_external = tk.edit_compose_external;
  window.addEventListener("focusin", compose_focus_handler, true);
  window.addEventListener("focusout", compose_focus_handler, true);
  window.addEventListener("keydown", compose_keydown_handler, true);
  attach_editor_window();
  compose_focus_handler();
  tk.editor_teardown = () => {
    window.removeEventListener("focusin", compose_focus_handler, true);
    window.removeEventListener("focusout", compose_focus_handler, true);
    window.removeEventListener("keydown", compose_keydown_handler, true);
    if (inner_editor_window) {
      inner_editor_window.removeEventListener("focusin", compose_focus_handler, true);
      inner_editor_window.removeEventListener("focusout", compose_focus_handler, true);
      inner_editor_window.removeEventListener("keydown", compose_keydown_handler, true);
    }
  };
})(window.tk);
