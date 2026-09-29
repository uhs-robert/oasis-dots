// home/quickshell/.config/quickshell/picker/KeybindsProvider.qml
import QtQuick
import Quickshell
import Quickshell.Io

// Described binds of one submap in Hyprland's order: Enter runs the bind. The mode arg is the submap open at the keypress.
PickerProvider {
    id: root

    name: "keybinds"
    title: root.submap !== "" ? "Keys: " + root.submap : "Keys"
    placeholder: "Search keybinds"
    verb: "run"
    rank_by_usage: false
    keep_order: true
    columns: 2
    grid_descriptions: true

    property string submap: ""

    readonly property var mod_bits: [
        { mask: 64, name: "SUPER" },
        { mask: 8, name: "ALT" },
        { mask: 4, name: "CTRL" },
        { mask: 1, name: "SHIFT" }
    ]

    function chord_of(bind) {
        const parts = root.mod_bits.filter(m => (bind.modmask & m.mask) !== 0).map(m => m.name);
        parts.push(bind.key);
        return parts.join("+");
    }

    function parse(text) {
        let binds = [];
        try {
            binds = JSON.parse(text);
        } catch (e) {
            console.warn("KeybindsProvider: invalid hyprctl output (" + e + ")");
        }
        const wanted = root.submap.toLowerCase();
        const items = binds.filter(b => b.has_description && b.submap.toLowerCase() === wanted).map(b => {
            const chord = root.chord_of(b);
            return { id: String(b.arg), label: b.description, description: chord, keywords: [chord, b.key], arg: b.arg, accent: b.description.startsWith("+") };
        });
        // Binds that enter a submap ("+Name") lead, as in which-key.
        return items.filter(i => i.accent).concat(items.filter(i => !i.accent));
    }

    // The bind ran inside its submap; leave it before the picker takes focus, as keybind-help.lua does.
    function refresh(arg) {
        root.submap = arg;
        root.items = [];
        list_proc.running = false;
        list_proc.running = true;
        Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.submap(\"reset\"))"]);
    }

    function activate(item) {
        Quickshell.execDetached(["hyprctl", "eval", "debug.getregistry()[" + item.arg + "]()"]);
    }

    Process {
        id: list_proc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.items = root.parse(text)
        }
    }
}
