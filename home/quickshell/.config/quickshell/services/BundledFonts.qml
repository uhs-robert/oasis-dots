// home/quickshell/.config/quickshell/services/BundledFonts.qml
import QtQuick
import "../theme"

// Registers the fonts the active style and lock skin use now, then the rest once startup settles.
Item {
    id: root

    // Family name to its files in fonts/; keep in step with fonts/README.md.
    readonly property var family_files: ({
        "Press Start 2P": ["PressStart2P-Regular.ttf"],
        "VT323": ["VT323-Regular.ttf"],
        "Silkscreen": ["Silkscreen-Regular.ttf", "Silkscreen-Bold.ttf"],
        "Exo 2": ["Exo2-Variable.ttf"],
        "Share Tech Mono": ["ShareTechMono-Regular.ttf"],
        "Orbitron": ["Orbitron-Variable.ttf"],
        "Michroma": ["Michroma-Regular.ttf"],
        "B612 Mono": ["B612Mono-Regular.ttf", "B612Mono-Bold.ttf"],
        "Oxanium": ["Oxanium-Variable.ttf"],
        "DSEG7 Classic": ["DSEG7Classic-Regular.ttf", "DSEG7Classic-Bold.ttf"],
        "Jura": ["Jura-Variable.ttf"],
        "Saira": ["Saira-Variable.ttf"],
        "Barlow Condensed": ["BarlowCondensed-Regular.ttf", "BarlowCondensed-Medium.ttf", "BarlowCondensed-SemiBold.ttf", "BarlowCondensed-Bold.ttf"],
        "Chakra Petch": ["ChakraPetch-Medium.ttf", "ChakraPetch-Bold.ttf"],
        "Nunito": ["Nunito-Variable.ttf"],
        "Inter": ["Inter-Light.ttf", "Inter-Regular.ttf", "Inter-Medium.ttf", "Inter-SemiBold.ttf"],
        "Geist": ["Geist-Variable.ttf"],
        "Geist Mono": ["GeistMono-Variable.ttf"],
        "Cormorant SC": ["CormorantSC-SemiBold.ttf"],
        "Cinzel": ["Cinzel-Variable.ttf"],
        "Belleza": ["Belleza-Regular.ttf"],
        "Rounded Mplus 1c": ["MPLUSRounded1c-Medium.ttf", "MPLUSRounded1c-ExtraBold.ttf"]
    })

    // Families hardcoded by a lock skin or style component rather than read from a Style token.
    readonly property var lock_families: ({
        crt: ["VT323"],
        tie: ["B612 Mono", "Oxanium"],
        mgs2: ["Barlow Condensed"],
        ff7: ["Nunito"],
        ocarina: ["Rounded Mplus 1c", "Belleza", "Cormorant SC", "Cinzel"],
        goldeneye: ["Michroma", "Share Tech Mono", "DSEG7 Classic"]
    })
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
        for (const file of files) {
            if (root.seen[file]) continue;
            root.seen[file] = true;
            fonts.append({ file: file });
        }
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
            root.rest = Object.keys(root.family_files);
            drip.start();
        }
    }

    Timer {
        id: drip
        interval: 40
        repeat: true
        onTriggered: {
            if (root.rest.length === 0) stop();
            else root.register(root.rest.shift());
        }
    }

    ListModel {
        id: fonts
    }

    Instantiator {
        model: fonts
        delegate: FontLoader {
            required property string file
            source: Qt.resolvedUrl("../fonts/" + file)
        }
    }
}
