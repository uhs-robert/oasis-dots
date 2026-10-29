import QtQuick
import qs.theme

// The mode chip at the left of a hint bar: the mode's name in the title style, with any status lines given as children
// stacked under it, or set beside it on one line with `inline` (a bar laid out above its groups).
Rectangle {
    id: root
    property string title: ""
    property bool inline: false
    default property alias lines: block.data
    // The width it takes stacked, whatever `inline` is, so a caller can pick a layout without a binding loop.
    readonly property real stacked_width: {
        let widest = 0;
        for (const child of block.children) {
            if (child.visible) widest = Math.max(widest, child.implicitWidth);
        }
        return widest + 24;
    }

    width: block.implicitWidth + 24
    height: block.implicitHeight + 14
    radius: Math.min(Style.frame_radius, 4)
    color: Style.title_bg
    Grid {
        id: block
        anchors.centerIn: parent
        // Enough columns for every line, so `inline` keeps them on one row.
        columns: root.inline ? 8 : 1
        columnSpacing: 12
        rowSpacing: 2
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        Text {
            text: root.title
            color: Style.title_fg
            font.family: Style.title_font_family
            font.pixelSize: Style.fs(0)
            font.bold: true
        }
    }
}
