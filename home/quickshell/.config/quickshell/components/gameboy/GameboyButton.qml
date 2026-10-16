import QtQuick
import qs.theme
import qs.components.nes as Nes

// The NES pad art in the Game Boy's four shades: round A/B, START/SELECT pills and the D-pad.
Nes.NesButton {
    shades: [Style.shade_0, Style.shade_1, Style.shade_2, Style.shade_3]
}
