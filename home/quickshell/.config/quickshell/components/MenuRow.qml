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
    color: root.selected && !Style.fade_fills ? Style.selection_bg : "transparent"
    border.width: root.selected && Style.selection_border.a > 0 ? 1 : 0
    border.color: Style.selection_border

    // A soft static halo behind the selected row.
    Repeater {
        model: root.selected && Style.selection_glow.a > 0 ? [2, 4, 6] : []

        Rectangle {
            required property int modelData
            z: -1
            anchors.fill: parent
            anchors.margins: -modelData
            radius: root.radius + modelData
            color: Qt.alpha(Style.selection_glow, Style.selection_glow.a * (0.5 - modelData * 0.06))
        }
    }

    // Styles with an inverse selection repaint the row's text and glyphs in one color.
    function fg(c) {
        return root.selected && Style.selection_inverse ? Style.selection_fg : c;
    }

    FadeFill {
        visible: root.selected && Style.fade_fills
        fill: Style.selection_bg
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
