import QtQuick
import Qt.labs.folderlistmodel
import "FontFiles.js" as FontFiles

// Registers the fonts the active style and lock skin use now, then the rest once startup settles.
Item {
    id: root

    readonly property var family_files: FontFiles.family_files

    // Families hardcoded by a lock skin or style component rather than read from a Style token.
    readonly property var lock_families: {
        const out = {};
        for (const key of Object.keys(Style.lock_skins)) out[key] = Style.lock_skins[key].fonts || [];
        return out;
    }
    readonly property var style_families: ({
        ps1: ["DSEG7 Classic"],
        ps2: ["Exo 2"],
        nes: ["Press Start 2P"],
        gameboy: ["Silkscreen"],
        snes: ["Silkscreen", "Press Start 2P"]
    })

    readonly property var wanted_families: [
        Style.font_family, Style.bar_font_family, Style.title_font_family, Style.number_font,
        Style.label_font_family, Style.mono_font, Style.bar_clock_font
    ].concat(root.lock_families[Style.lock_name] || [], root.style_families[Style.name] || [])

    property var seen: ({})
    property var rest: []

    function register(family) {
        const files = root.family_files[family];
        if (!files) return;
        for (const file of files) root.register_file(file);
    }

    function register_file(file) {
        if (root.seen[file]) return;
        root.seen[file] = true;
        fonts.append({ file: file });
    }

    function register_wanted() {
        for (const family of root.wanted_families) root.register(family);
    }

    onWanted_familiesChanged: register_wanted()
    Component.onCompleted: register_wanted()

    Timer {
        interval: 2000
        running: true
        onTriggered: {
            lister.active = true;
            root.warn_missing_symbols();
        }
    }

    // Bar and popup glyphs are Nerd Font codepoints; `lib/install/fonts.sh` installs Maple Mono NF and `arch.ini` the JetBrains and Symbols ones; other machines may lack them.
    function warn_missing_symbols() {
        const installed = Qt.fontFamilies().map(f => f.replace(/ \[[^\]]*\]$/, "").toLowerCase());
        const missing = [Theme.font_family, "JetBrainsMono Nerd Font", "Symbols Nerd Font"].filter(f => installed.indexOf(f.toLowerCase()) < 0);
        if (missing.length > 0) console.warn("BundledFonts: font(s) not installed, icons may show as boxes: " + missing.join(", "));
    }

    // Read once after startup so a font missing from the map still loads.
    Loader {
        id: lister
        active: false
        sourceComponent: FolderListModel {
            folder: Qt.resolvedUrl("../assets/fonts")
            nameFilters: ["*.ttf", "*.otf"]
            showDirs: false
            onStatusChanged: if (status === FolderListModel.Ready) {
                const names = [];
                for (let i = 0; i < count; i++) names.push(get(i, "fileName"));
                root.rest = names;
                drip.start();
                Qt.callLater(() => lister.active = false);
            }
        }
    }

    Timer {
        id: drip
        interval: 40
        repeat: true
        onTriggered: {
            if (root.rest.length === 0) stop();
            else root.register_file(root.rest.shift());
        }
    }

    ListModel {
        id: fonts
    }

    Instantiator {
        model: fonts
        delegate: FontLoader {
            required property string file
            source: Qt.resolvedUrl("../assets/fonts/" + file)
        }
    }
}
