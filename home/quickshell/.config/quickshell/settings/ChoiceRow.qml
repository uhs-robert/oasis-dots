// home/quickshell/.config/quickshell/settings/ChoiceRow.qml
import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"

// A setting shown as its label and current value; a click on the left or right half steps it.
MenuRow {
    id: root

    property string label: ""
    property string value_text: ""
    readonly property bool hovered: mouse_area.containsMouse

    signal stepped(int delta)

    Layout.fillWidth: true
    Layout.preferredHeight: Style.px(28)
    base_radius: 6

    RowLayout {
        id: row_layout
        anchors.left: parent.left
        anchors.leftMargin: 8 + root.inset
        anchors.right: parent.right
        anchors.rightMargin: 8 + root.key_space
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        RowLabel {
            id: row_label
            Layout.fillWidth: true
            label: root.label
            color: root.fg(root.st.text_fg)
            font.family: root.st.font_family
            font.pixelSize: root.st.font_size
        }

        Text {
            // A long value (a path, a borrowed skin shared by several styles) shortens in the middle instead of running into the label.
            Layout.maximumWidth: Math.max(0, Math.min(root.width * 0.65, row_layout.width - row_label.implicitWidth - row_layout.spacing))
            elide: Text.ElideMiddle
            text: root.st.toggle_brackets ? "[" + root.value_text.toUpperCase() + "]" : root.selected ? "‹ " + root.value_text + " ›" : root.value_text
            color: root.fg(root.selected ? root.st.toggle_on : root.st.text_dim)
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
        }
    }

    MouseArea {
        id: mouse_area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: mouse => root.stepped(mouse.x < root.width / 2 ? -1 : 1)
    }
}
