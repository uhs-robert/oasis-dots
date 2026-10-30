.pragma library

// What the directory segment shows for the focused window, given the three Settings switches.

var default_switches = { app_name: true, path: true, file_name: true };

// Lualine-style path: ~ for $HOME, the last dir and its two parents whole (plus the file name), higher dirs to one
// letter except dot-folders, then 48 chars at most, cut from the left.
function shorten(path, is_file, home) {
    if (path === "") return "";
    const p = home && (path === home || path.startsWith(home + "/")) ? "~" + path.slice(home.length) : path;
    const parts = p.split("/");
    const keep = parts.length - (is_file ? 4 : 3);
    const short = parts.map((d, i) => i >= keep || d === "" || d === "~" || d.startsWith(".") ? d : d.charAt(0)).join("/");
    if (short.length <= 48) return short;
    const tail = short.slice(short.length - 46);
    const cut = tail.indexOf("/");
    return "…/" + (cut >= 0 ? tail.slice(cut + 1) : tail);
}

// Whether a window class is a terminal: a known class, or one that extends it after a dash (tmuxifier names its
// windows kitty-tmux-<session>). The dash keeps look-alikes such as kittyfoo out.
function is_terminal_class(cls, terminal_classes) {
    const c = cls.toLowerCase();
    return terminal_classes.some(t => c === t || c.startsWith(t + "-"));
}

// window-cwd's output split into the program it names (an optional "app:<name>" first line) and the rest.
function parse(output) {
    const lines = output.trim().split("\n");
    const app = lines.length > 0 && lines[0].startsWith("app:") ? lines.shift().slice(4) : "";
    return { app: app, path: lines.join("\n").trim() };
}

// The path text for window-cwd's path ("file:<path>" for an open Neovim file, else a directory).
// The path switch governs directories; the file switch governs the file name, which stands alone when the path is off.
function path_text(path_output, switches, home) {
    const out = path_output.trim();
    if (out === "") return "";
    if (!out.startsWith("file:")) return switches.path ? shorten(out, false, home) : "";
    const file = out.slice(5);
    const cut = file.lastIndexOf("/");
    if (switches.path && switches.file_name) return shorten(file, true, home);
    if (switches.path) return shorten(cut > 0 ? file.slice(0, cut) : "/", false, home);
    return switches.file_name ? file.slice(cut + 1) : "";
}

// The tooltip: app name and the whole path, untruncated (~ for $HOME), whatever the switches hide from the bar.
function tooltip_text(app_name, path_output, home) {
    const path = path_output.startsWith("file:") ? path_output.slice(5) : path_output;
    const shown = home && (path === home || path.startsWith(home + "/")) ? "~" + path.slice(home.length) : path;
    return [app_name, shown].filter(s => s !== "").join("\n");
}

function app_text(app_name, switches) {
    return switches.app_name ? app_name : "";
}
