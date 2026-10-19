pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Keyboard, mouse and touchpad choices saved in input.json under the Hyprland state dir; config/input applies them.
// Unsaved keys show Hyprland's live value, so a machine profile's choice reads correctly until it is overridden.
Singleton {
    id: root

    readonly property string state_dir: Paths.hypr_state_dir

    // Hyprland option behind each key.
    readonly property var options: ({
        kb_layout: "input:kb_layout",
        kb_variant: "input:kb_variant",
        repeat_rate: "input:repeat_rate",
        repeat_delay: "input:repeat_delay",
        sensitivity: "input:sensitivity",
        follow_mouse: "input:follow_mouse",
        natural_scroll: "input:touchpad:natural_scroll",
        tap_to_click: "input:touchpad:tap-to-click",
        disable_while_typing: "input:touchpad:disable_while_typing"
    })

    // Config.input's defaults until Hyprland answers.
    readonly property var fallback: ({ kb_layout: "us", kb_variant: "", repeat_rate: 25, repeat_delay: 600, sensitivity: 0, follow_mouse: 1, natural_scroll: false, tap_to_click: true, disable_while_typing: true, which_key_delay_ms: 0, pointer_keys: "hjkl" })
    property var live: root.fallback
    readonly property var saved: store.values
    property bool reload_pending: false

    // XKB layouts and variants from base.lst: layouts [{ code, name }], variants { layout: [{ code, name }] }.
    property var layouts: []
    property var variants: ({})

    // Mirrors VALID in config/input, which ignores anything else, so the panel never shows a value Hyprland did not apply.
    function valid(key, v) {
        const integer_in = (min, max) => Number.isInteger(v) && v >= min && v <= max;
        switch (key) {
        case "kb_layout": return typeof v === "string" && /^[A-Za-z0-9_,-]+$/.test(v);
        case "kb_variant": return typeof v === "string" && /^[A-Za-z0-9_,-]*$/.test(v);
        case "natural_scroll":
        case "tap_to_click":
        case "disable_while_typing": return typeof v === "boolean";
        case "repeat_rate": return integer_in(1, 100);
        case "repeat_delay": return integer_in(100, 2000);
        case "sensitivity": return typeof v === "number" && v >= -1 && v <= 1;
        case "follow_mouse": return integer_in(0, 3);
        case "which_key_delay_ms": return integer_in(0, 5000);
        case "pointer_keys": return v === "hjkl" || v === "wasd" || v === "both";
        }
        return false;
    }

    function value(key) {
        return root.saved[key] !== undefined ? root.saved[key] : root.live[key];
    }

    function set(key, value) {
        const next = Object.assign({}, root.saved, { [key]: value });
        // A variant belongs to one layout.
        if (key === "kb_layout" && value !== root.value("kb_layout")) next.kb_variant = "";
        if (key === "which_key_delay_ms" || key === "pointer_keys") root.reload_pending = true;
        store.replace(next);
    }

    function layout_name(code) {
        const found = root.layouts.find(l => l.code === code);
        return found ? found.name : code;
    }

    function variant_name(layout, code) {
        if (code === "") return "Default";
        const found = (root.variants[layout] || []).find(v => v.code === code);
        return found ? found.name : code;
    }

    function parse_live(text) {
        const next = Object.assign({}, root.fallback);
        for (const chunk of text.split("\u001e")) {
            if (chunk.trim() === "") continue;
            try {
                const o = JSON.parse(chunk);
                if (o.option === undefined) {
                    for (const key in o) next[key] = o[key];
                    continue;
                }
                const raw = o.str !== undefined ? (o.str === "[[EMPTY]]" ? "" : o.str) : o.int !== undefined ? o.int : o.float !== undefined ? o.float : o.bool;
                for (const key in root.options) {
                    if (root.options[key] !== o.option) continue;
                    next[key] = raw;
                }
            } catch (e) {
                console.warn("HyprInput: unreadable getoption output (" + e + ")");
            }
        }
        root.live = next;
    }

    function parse_xkb(text) {
        const layouts = [];
        const variants = {};
        let section = "";
        for (const line of text.split("\n")) {
            if (line.indexOf("! ") === 0) {
                section = line.slice(2).trim();
                continue;
            }
            const m = line.match(/^\s+(\S+)\s+(.*)$/);
            if (!m) continue;
            if (section === "layout") {
                layouts.push({ code: m[1], name: m[2] });
            } else if (section === "variant") {
                const v = m[2].match(/^(\S+): (.*)$/);
                if (!v) continue;
                (variants[v[1]] = variants[v[1]] || []).push({ code: m[1], name: v[2] });
            }
        }
        root.layouts = layouts.sort((a, b) => a.name.localeCompare(b.name));
        root.variants = variants;
    }

    Component.onCompleted: live_proc.running = true

    Process {
        id: live_proc
        // which_key_delay_ms and pointer_keys are Config.input values, not Hyprland options, and hyprctl eval prints nothing back, so they go through a file.
        command: ["sh", "-c", 'for o in "$@"; do hyprctl getoption "$o" -j; printf "\\036"; done; f="$XDG_RUNTIME_DIR/qs-input-config"; hyprctl eval "local i = require(\'config\').input; local f = io.open(\'$f\', \'w\'); f:write(string.format(\'{\\"which_key_delay_ms\\":%d,\\"pointer_keys\\":\\"%s\\"}\', i.which_key_delay_ms or 0, i.pointer_keys or \'hjkl\')); f:close()" >/dev/null && cat "$f"', "sh"].concat(Object.values(root.options).filter((o, i, all) => all.indexOf(o) === i))
        stdout: StdioCollector {
            onStreamFinished: root.parse_live(text)
        }
    }

    FileView {
        path: "/usr/share/X11/xkb/rules/base.lst"
        printErrors: false
        onLoaded: root.parse_xkb(text())
    }

    JsonStore {
        id: store
        path: root.state_dir + "/input.json"
        debounce_ms: 500
        // Listing every key the panel can drop keeps it from coming back out of the file as an unknown key.
        known_keys: Object.keys(root.options).concat(["which_key_delay_ms", "pointer_keys"])
        validate: raw => {
            const next = {};
            for (const key in raw) {
                if (root.valid(key, raw[key])) next[key] = raw[key];
            }
            return next;
        }
        after_save: values => {
            // HyprVim reads its which-key delay and the Cursor submap its keys only at setup, so those changes need a reload.
            const argv = root.reload_pending ? ["hyprctl", "reload"] : ["hyprctl", "eval", 'require("config.input").apply()'];
            root.reload_pending = false;
            return argv;
        }
        onAfter_save_done: live_proc.running = true
    }
}
