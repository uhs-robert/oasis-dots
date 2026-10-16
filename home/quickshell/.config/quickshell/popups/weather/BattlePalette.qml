import QtQuick
import "../../theme"

// The NES palette NesSprites.js rows index: 0 dark, 1 white, 2 yellow, 3 bright yellow, 4 blue, 5 light blue, 6 grey, 7 red, 8 shadow grey.
QtObject {
    readonly property var colors: [Style.pal.bg_crust, Style.pal.fg_strong, Style.pal.yellow, Style.pal.bright_yellow, Style.pal.blue, Style.pal.bright_blue, Style.pal.fg_dim, Style.pal.red, Style.pal.fg_muted]
}
