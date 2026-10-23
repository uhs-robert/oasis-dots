import QtQuick
import QtQuick.Shapes

// A band's vertical shade (BandFill, DrawerShape): `shade_color` at the screen edge into `color` at the band's open edge
// `thickness` on, flat past it. `offset` is how far the fill's own origin lies past the band's, so a drawer hung from inside
// the band picks the shade up at the same row.
LinearGradient {
    id: root

    property color shade_color: "transparent"
    property color color: "transparent"
    property real thickness: 0
    property real offset: 0

    x1: 0
    y1: -root.offset
    x2: 0
    y2: root.thickness - root.offset
    GradientStop { position: 0; color: root.shade_color }
    GradientStop { position: 1; color: root.color }
}
