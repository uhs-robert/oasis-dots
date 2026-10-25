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

// The path text for window-cwd's output ("file:<path>" for an open Neovim file, else a directory).
// The path switch governs directories; the file switch governs the file name, which stands alone when the path is off.
function path_text(output, switches, home) {
    const out = output.trim();
    if (out === "") return "";
    if (!out.startsWith("file:")) return switches.path ? shorten(out, false, home) : "";
    const file = out.slice(5);
    const cut = file.lastIndexOf("/");
    if (switches.path && switches.file_name) return shorten(file, true, home);
    if (switches.path) return shorten(cut > 0 ? file.slice(0, cut) : "/", false, home);
    return switches.file_name ? file.slice(cut + 1) : "";
}

function app_text(app_name, switches) {
    return switches.app_name ? app_name : "";
}
