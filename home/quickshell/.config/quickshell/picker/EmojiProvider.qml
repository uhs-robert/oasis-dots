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
    // Qt never falls back from one icon font to another, so each glyph names the font that covers it.
    readonly property var set_fonts: ({
        fontawesome: [
            { family: "Font Awesome 7 Free", weight: Font.Black, pattern: "Font Awesome 7 Free:style=Solid" },
            { family: "Font Awesome 7 Brands", weight: Font.Normal, pattern: "Font Awesome 7 Brands" }
        ]
    })

    property string set_name: "emoji"
    glyph_font: root.set_name === "nerd_font" || root.set_name === "fontawesome" ? "Symbols Nerd Font" : ""
    property string loading_set: ""
    // set -> parsed items, filled on first use.
    property var cache: ({})

    // fc-list charset ("20-7e a0 ...") -> { codepoint: true }.
    function charset(text) {
        const out = {};
        for (const part of text.trim().split(/\s+/)) {
            if (part === "") continue;
            const [a, b] = part.split("-").map(h => parseInt(h, 16));
            for (let c = a; c <= (b === undefined ? a : b); c++) out[c] = true;
        }
        return out;
    }

    function parse(text, fonts) {
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
            const item = { id: glyph, label: label, glyph: glyph, keywords: keywords };
            const font = fonts.find(f => f.chars[glyph.codePointAt(0)]);
            if (font) {
                item.glyph_font = font.family;
                item.glyph_weight = font.weight;
            }
            out.push(item);
        }
        return out;
    }

    function load(set) {
        if (load_proc.running) return;
        root.loading_set = set;
        const charsets = (root.set_fonts[set] || []).map(f => "; printf '\\036'; fc-list -f '%{charset}\\n' '" + f.pattern + "'").join("");
        load_proc.command = ["sh", "-c", "cat " + root.data_dir + "/" + root.globs[set] + charsets];
        load_proc.running = true;
    }

    function loaded(text) {
        const set = root.loading_set;
        const next = Object.assign({}, root.cache);
        const parts = text.split("\x1e");
        const fonts = (root.set_fonts[set] || []).map((f, i) => Object.assign({ chars: root.charset(parts[i + 1] || "") }, f));
        next[set] = root.parse(parts[0], fonts);
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
