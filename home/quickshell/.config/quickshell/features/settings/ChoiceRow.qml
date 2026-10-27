import QtQuick
import QtQuick.Layouts
import qs.ui.menu
import qs.theme
import "SettingsScale.js" as SScale

// A setting shown as its label and current value; a click on the left or right half steps it.
MenuRow {
    id: root

    property string label: ""
    property string value_text: ""
    // Nesting depth, for a row that refines the one above it.
    property int indent: 0
    // Where the value starts, from the label's unindented left edge; below 0 the value sits at the row's right end.
    property real value_x: -1
    readonly property bool in_column: root.value_x >= 0
    readonly property bool hovered: mouse_area.containsMouse
    readonly property int bump: SScale.bump_of(root)
    // Unselected values lean toward the label color so they read on dark panels.
    readonly property color value_fg: {
        const c = SScale.lifted(root.st.text_dim, root.st.text_fg, 0.6);
        return Qt.rgba(c[0], c[1], c[2], c[3]);
    }

    signal stepped(int delta)

    Layout.fillWidth: true
    Layout.preferredHeight: Style.px(28) + SScale.pitch_extra(root.bump)
    base_radius: 6

    RowLayout {
        id: row_layout
        anchors.left: parent.left
        anchors.leftMargin: 8 + root.inset + root.indent * Style.px(14)
        anchors.right: parent.right
        anchors.rightMargin: 8 + root.key_space
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        RowLabel {
            id: row_label
            Layout.fillWidth: !root.in_column
            // The selected value's leading arrow hangs left of the column, so the value itself does not move.
            Layout.preferredWidth: root.in_column ? Math.max(0, root.value_x - root.indent * Style.px(14) - row_layout.spacing - (root.selected && !root.st.toggle_brackets ? arrow_metrics.advanceWidth("‹ ") : 0)) : -1
            elide: root.in_column ? Text.ElideRight : Text.ElideNone
            label: root.label
            color: root.fg(root.st.text_fg)
            font.family: root.st.font_family
            font.pixelSize: root.st.font_size + root.bump
        }

        Text {
            id: value_label
            Layout.fillWidth: root.in_column
            // A long value (a path, a borrowed skin shared by several styles) shortens in the middle instead of running into the label.
            Layout.maximumWidth: root.in_column ? Number.POSITIVE_INFINITY : Math.max(0, Math.min(root.width * 0.65, row_layout.width - row_label.implicitWidth - row_layout.spacing))
            elide: Text.ElideMiddle
            text: root.st.toggle_brackets ? "[" + root.value_text.toUpperCase() + "]" : root.selected ? "‹ " + root.value_text + " ›" : root.value_text
            color: root.fg(root.selected ? root.st.toggle_on : root.value_fg)
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2) + root.bump
        }
    }

    FontMetrics {
        id: arrow_metrics
        font: value_label.font
    }

    MouseArea {
        id: mouse_area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: mouse => root.stepped(mouse.x < root.width / 2 ? -1 : 1)
    }
}
