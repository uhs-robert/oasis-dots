// home/quickshell/.config/quickshell/picker/EmojiProvider.qml
import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

// rofimoji character sets, one per tab: Enter types the character into the previous window, `y` copies it.
PickerProvider {
    id: root

    name: "emoji"
    title: "Emoji"
    placeholder: "Search characters"
    columns: 4
    verb: "type"
    max_results: 300
    actions: [{ key: "y", desc: "copy" }]

    readonly property string data_dir: "/usr/lib/python3.*/site-packages/picker/data"
    readonly property var globs: ({
        emoji: "emojis_*.csv",
        nerd_font: "nerd_font.csv",
        gitmoji: "gitmoji.csv",
        fontawesome: "fontawesome6.csv"
    })
    readonly property var sets: ["emoji", "gitmoji", "fontawesome", "nerd_font"]
    tabs: ["Emoji", "GitHub", "Font Awesome", "Nerd Font"]

    property string set_name: "emoji"
    property string loading_set: ""
    // set -> parsed items, filled on first use.
    property var cache: ({})

    function parse(text) {
        const out = [];
        const seen = {};
        for (const line of text.split("\n")) {
            const sp = line.indexOf(" ");
            if (sp <= 0) continue;
            const glyph = line.slice(0, sp);
            if (seen[glyph]) continue;
            seen[glyph] = true;
            let label = line.slice(sp + 1).trim();
            let keywords = [];
            const m = /^(.*?)\s*<small>\((.*)\)<\/small>$/.exec(label);
            if (m) {
                label = m[1];
                keywords = m[2].split(", ");
            }
            out.push({ id: glyph, label: label, glyph: glyph, keywords: keywords });
        }
        return out;
    }

    function load(set) {
        if (load_proc.running) return;
        root.loading_set = set;
        load_proc.command = ["sh", "-c", "cat " + root.data_dir + "/" + root.globs[set]];
        load_proc.running = true;
    }

    function loaded(text) {
        const set = root.loading_set;
        const next = Object.assign({}, root.cache);
        next[set] = root.parse(text);
        root.cache = next;
        root.loading_set = "";
        if (root.set_name === set) root.items = next[set];
        else if (root.cache[root.set_name] === undefined) root.load(root.set_name);
    }

    function refresh(arg) {
        root.select_tab(Math.max(0, root.sets.indexOf(arg)));
    }

    function select_tab(i) {
        const set = root.sets[i];
        root.tab = i;
        root.set_name = set;
        if (root.cache[set] !== undefined) {
            root.items = root.cache[set];
            return;
        }
        root.items = [];
        root.load(set);
    }

    property string pending_glyph: ""

    // Types from a timer so the picker's close has run before wtype targets the focused window.
    function activate(item) {
        root.pending_glyph = item.glyph;
        type_timer.restart();
    }

    function run_action(key, item) {
        if (key !== "y") return;
        Pickers.close();
        Quickshell.execDetached(["wl-copy", "--", item.glyph]);
    }

    Timer {
        id: type_timer
        interval: 150
        onTriggered: Quickshell.execDetached(["wtype", "--", root.pending_glyph])
    }

    Process {
        id: load_proc
        stdout: StdioCollector {
            onStreamFinished: root.loaded(text)
        }
    }
}
