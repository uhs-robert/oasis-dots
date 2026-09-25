// home/quickshell/.config/quickshell/components/MenuRow.qml
import QtQuick
import "../theme"

Rectangle {
    id: root

    readonly property var st: Style.for_item(root)

    property bool selected: false
    property real base_radius: 4
    // A slot number the style's row marker may show; -1 for none.
    property int slot: -1
    readonly property bool marked: root.st.row_marker !== ""
    // Room reserved at the left for the style's cursor marker; rows add it to their left margin.
    readonly property real inset: root.marked ? 16 : root.st.hand_cursor ? 24 : root.st.row_cursor !== "" ? cursor_text.implicitWidth + 4 : 0
    // The row's shortcut, drawn as a badge at the right by styles that show row keys.
    property string key: ""
    readonly property bool show_key: root.st.row_keys && root.key !== ""
    readonly property real key_space: (root.show_key ? key_badge.width + 6 : 0)

    radius: Style.radius(root.base_radius)
    color: root.selected && !root.st.fade_fills ? root.st.selection_bg : "transparent"
    border.width: root.selected && root.st.selection_border.a > 0 ? 1 : 0
    border.color: root.st.selection_border

    // A soft static halo behind the selected row.
    Repeater {
        model: root.selected && root.st.selection_glow.a > 0 ? [2, 4, 6] : []

        Rectangle {
            required property int modelData
            z: -1
            anchors.fill: parent
            anchors.margins: -modelData
            radius: root.radius + modelData
            color: Qt.alpha(root.st.selection_glow, root.st.selection_glow.a * (0.5 - modelData * 0.06))
        }
    }

    // Styles with an inverse selection repaint the row's text and glyphs in one color.
    function fg(c) {
        return root.selected && root.st.selection_inverse ? root.st.selection_fg : c;
    }

    FadeFill {
        visible: root.selected && root.st.fade_fills
        fill: root.st.selection_bg
    }

    DashedOutline {
        visible: root.selected && root.st.selection_outline.a > 0
        anchors.fill: parent
        anchors.margins: 1
        color: root.st.selection_outline
    }

    LockBrackets {
        shown: root.selected
    }

    Rectangle {
        visible: root.selected && root.st.selection_bar
        width: 2
        height: parent.height
        color: root.st.caret_color
    }

    Rectangle {
        visible: root.st.row_rule.a > 0 || root.selected && root.st.selection_rule.a > 0
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: root.selected && root.st.selection_rule.a > 0 ? root.st.selection_rule : root.st.row_rule
    }

    CornerTick {
        visible: root.selected && root.st.corner_tick.a > 0
        color: root.st.selection_rule.a > 0 ? root.st.selection_rule : root.st.corner_tick
    }

    Rectangle {
        visible: root.marked && root.slot < 0
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 7
        height: 7
        color: root.selected ? root.st.caret_color : "transparent"
        border.width: root.selected ? 0 : 1
        border.color: root.st.text_muted
    }

    Text {
        visible: root.marked && root.slot >= 0
        x: 5
        anchors.verticalCenter: parent.verticalCenter
        text: String(root.slot).padStart(2, "0")
        color: root.selected ? root.st.caret_color : root.st.text_muted
        font.family: root.st.mono_font
        font.pixelSize: root.st.font_size - 4
    }

    Text {
        id: cursor_text
        visible: root.selected && !root.marked && root.st.row_cursor !== "" && Style.caret_phase
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        text: root.st.row_cursor
        color: root.st.caret_color
        font.family: root.st.mono_font
        font.pixelSize: root.st.font_size - 1
        font.bold: true
    }

    HandCursor {
        visible: root.selected && !root.marked && root.st.hand_cursor
        x: 3
        anchors.verticalCenter: parent.verticalCenter
        width: 19
        height: 12
    }

    KeyBadge {
        id: key_badge
        visible: root.show_key
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        key: root.key
        on_fill: root.selected && root.st.selection_inverse
    }
}
