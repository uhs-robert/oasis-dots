// home/quickshell/.config/quickshell/services/HyprInput.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// Keyboard, mouse and touchpad choices saved in input.json under the Hyprland state dir; config/input applies them.
// Unsaved keys show Hyprland's live value, so a machine profile's choice reads correctly until it is overridden.
Singleton {
    id: root

    readonly property string state_dir: Paths.hypr_state_dir

    // Hyprland option behind each key; caps_escape is read out of kb_options.
    readonly property var options: ({
        kb_layout: "input:kb_layout",
        kb_variant: "input:kb_variant",
        caps_escape: "input:kb_options",
        repeat_rate: "input:repeat_rate",
        repeat_delay: "input:repeat_delay",
        sensitivity: "input:sensitivity",
        follow_mouse: "input:follow_mouse",
        natural_scroll: "input:touchpad:natural_scroll",
        tap_to_click: "input:touchpad:tap-to-click",
        disable_while_typing: "input:touchpad:disable_while_typing"
    })

    // Config.input's defaults until getoption answers; which_key_delay_ms is HyprVim's, not a Hyprland option, so it stays the default.
    readonly property var fallback: ({ kb_layout: "us", kb_variant: "", caps_escape: false, repeat_rate: 25, repeat_delay: 600, sensitivity: 0, follow_mouse: 1, natural_scroll: false, tap_to_click: true, disable_while_typing: true, which_key_delay_ms: 0 })
    property var live: root.fallback
    property var saved: ({})
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
        case "caps_escape":
        case "natural_scroll":
        case "tap_to_click":
        case "disable_while_typing": return typeof v === "boolean";
        case "repeat_rate": return integer_in(1, 100);
        case "repeat_delay": return integer_in(100, 2000);
        case "sensitivity": return typeof v === "number" && v >= -1 && v <= 1;
        case "follow_mouse": return integer_in(0, 3);
        case "which_key_delay_ms": return integer_in(0, 5000);
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
        if (key === "which_key_delay_ms") root.reload_pending = true;
        root.saved = next;
        save_timer.restart();
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
                const raw = o.str !== undefined ? (o.str === "[[EMPTY]]" ? "" : o.str) : o.int !== undefined ? o.int : o.float !== undefined ? o.float : o.bool;
                for (const key in root.options) {
                    if (root.options[key] !== o.option) continue;
                    next[key] = key === "caps_escape" ? raw.split(",").indexOf("caps:escape") >= 0 : raw;
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
        command: ["sh", "-c", 'for o in "$@"; do hyprctl getoption "$o" -j; printf "\\036"; done', "sh"].concat(Object.values(root.options).filter((o, i, all) => all.indexOf(o) === i))
        stdout: StdioCollector {
            onStreamFinished: root.parse_live(text)
        }
    }

    FileView {
        path: "/usr/share/X11/xkb/rules/base.lst"
        printErrors: false
        onLoaded: root.parse_xkb(text())
    }

    Timer {
        id: save_timer
        interval: 500
        onTriggered: {
            if (save_proc.running) {
                save_timer.restart();
                return;
            }
            // HyprVim reads its which-key delay only at setup, so that one change needs a reload.
            const apply = root.reload_pending ? "hyprctl reload" : "hyprctl eval 'require(\"config.input\").apply()'";
            root.reload_pending = false;
            save_proc.command = ["sh", "-c", "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/input.json.tmp\" && mv \"$1/input.json.tmp\" \"$1/input.json\" && " + apply,
                "sh", root.state_dir, JSON.stringify(root.saved)];
            save_proc.running = true;
        }
    }

    Process {
        id: save_proc
        onExited: live_proc.running = true
    }

    FileView {
        path: root.state_dir + "/input.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                const next = {};
                for (const key in data) {
                    if (root.valid(key, data[key])) next[key] = data[key];
                }
                root.saved = next;
            } catch (e) {
                console.warn("HyprInput: invalid input.json (" + e + ")");
            }
        }
        onLoadFailed: error => {}
    }
}
