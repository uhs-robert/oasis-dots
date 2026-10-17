import QtQuick
import qs.ui.gauges
import qs.theme

// A Pokédex base-stat bar in the Game Boy shades: segments lit up to `value`, the last lit one brightest.
Item {
    id: root

    property real value: 0
    // A range bar always shows its marker, even at 0, since there it means "at the low".
    property bool range: false
    readonly property int count: Math.max(6, Math.floor(root.width / 6))
    readonly property real v: Math.max(0, Math.min(1, root.value))
    readonly property int marker: root.range ? Math.min(root.count - 1, Math.floor(root.v * root.count)) : Math.round(root.v * root.count) - 1

    implicitHeight: 6

    SegBar {
        anchors.fill: parent
        count: root.count
        last_lit: root.marker - 1
        on_color: Style.pixel_shades[2]
        off_color: Style.pixel_shades[1]
    }

    SegBar {
        anchors.fill: parent
        count: root.count
        first_lit: root.marker
        last_lit: root.marker
        on_color: Style.pixel_shades[3]
    }
}
