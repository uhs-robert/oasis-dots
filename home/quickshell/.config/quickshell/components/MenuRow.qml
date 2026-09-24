// home/quickshell/.config/quickshell/components/MenuRow.qml
import QtQuick
import "../theme"

Rectangle {
    id: root

    property bool selected: false
    property real base_radius: 4
    // Room reserved at the left for the style's cursor marker; rows add it to their left margin.
    readonly property real inset: Style.row_cursor !== "" ? cursor_text.implicitWidth + 4 : 0
    // The row's shortcut, drawn as a badge at the right by styles that show row keys.
    property string key: ""
    readonly property bool show_key: Style.row_keys && root.key !== ""
    readonly property real key_space: root.show_key ? key_badge.width + 6 : 0

    radius: Style.radius(root.base_radius)
    color: root.selected ? Style.selection_bg : "transparent"

    // Styles with an inverse selection repaint the row's text and glyphs in one color.
    function fg(c) {
        return root.selected && Style.selection_inverse ? Style.selection_fg : c;
    }

    DashedOutline {
        visible: root.selected && Style.selection_outline.a > 0
        anchors.fill: parent
        anchors.margins: 1
        color: Style.selection_outline
    }

    Rectangle {
        visible: root.selected && Style.selection_bar
        width: 2
        height: parent.height
        color: Style.caret_color
    }

    Text {
        id: cursor_text
        visible: root.selected && Style.row_cursor !== "" && Style.caret_phase
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        text: Style.row_cursor
        color: Style.caret_color
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 1
        font.bold: true
    }

    KeyBadge {
        id: key_badge
        visible: root.show_key
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        key: root.key
    }
}
