// home/quickshell/.config/quickshell/components/snes/MapStar.qml
import QtQuick
import "../../theme"
import ".."

// The overworld's pixel-art yellow star, 9 px square at 1x.
PixelSprite {
    pixel: 1
    colors: [Theme.bg_shadow, Theme.theme_secondary]
    rows: ["....0....", "...010...", "000111000", "011111110", ".0111110.", "..01110..", ".0110110.", ".010.010.", ".00...00."]
}
