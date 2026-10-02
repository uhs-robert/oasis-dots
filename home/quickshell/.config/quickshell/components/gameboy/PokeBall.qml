// home/quickshell/.config/quickshell/components/gameboy/PokeBall.qml
import QtQuick
import "../../theme"
import ".."

// A Poke Ball per closed workspace: whole when it holds windows, an outline when empty. Red and white on the Color, shades on the original.
PixelSprite {
    id: root

    property bool full: true
    property bool lit: false
    readonly property bool mono: Style.device_model === "dmg"
    readonly property color line: root.lit ? Style.shade_3 : root.mono ? Style.shade_2 : Theme.fg_dim

    pixel: 1
    colors: !root.full ? [root.line, root.line, root.line, root.line]
        : root.mono ? [Style.shade_0, Style.shade_2, Style.shade_3, Style.shade_3]
        : [Theme.bg_crust, Theme.red, Theme.fg_strong, Qt.tint(Theme.red, Qt.alpha(Theme.fg_strong, 0.6))]
    rows: root.full ? [
        "....000000....",
        "..0011111100..",
        ".011331111110.",
        ".011311111110.",
        "01111111111110",
        "01111000011110",
        "00000022000000",
        "00000022000000",
        "02222000022220",
        "02222222222220",
        ".022222222220.",
        ".022222222220.",
        "..0022222200..",
        "....000000...."
    ] : [
        "....000000....",
        "..00......00..",
        ".0..........0.",
        ".0..........0.",
        "0............0",
        "0....0000....0",
        "000000..000000",
        "000000..000000",
        "0....0000....0",
        "0............0",
        ".0..........0.",
        ".0..........0.",
        "..00......00..",
        "....000000...."
    ]
}
