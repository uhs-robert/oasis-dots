// home/quickshell/.config/quickshell/components/ToggleRow.qml
import QtQuick
import QtQuick.Layouts
import "../theme"

// A popup's main on/off switch, toggled by t, Enter on the row or a click.
MenuRow {
    id: root

    property string label: ""
    property bool checked: false
    property bool show_state: true
    property string toggle_key: "t"
    // Replaces On/Off for rows with more than two states.
    property string state_label: ""
    // Bracketed styles pad the row like a list row; the default stays flush.
    readonly property real pad: root.st.toggle_brackets ? 6 : 0

    signal toggled()

    key: root.show_state ? root.toggle_key : ""
    Layout.fillWidth: true
    implicitHeight: root.st.toggle_brackets ? Style.px(22) : content_row.implicitHeight

    RowLayout {
        id: content_row
        anchors.fill: parent
        anchors.leftMargin: root.pad + root.inset
        anchors.rightMargin: root.pad + root.key_space
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: root.label
            color: root.fg(root.st.text_strong)
            font.family: root.st.font_family
            font.pixelSize: root.st.font_size - 1
        }

        Text {
            visible: root.show_state
            text: root.state_label !== "" ? (root.st.toggle_brackets ? "[" + root.state_label.toUpperCase() + "]" : root.state_label) : root.st.toggle_brackets ? (root.checked ? "[ ON ]" : "[OFF]") : (root.checked ? "On" : "Off")
            color: root.fg(root.checked ? root.st.toggle_on : root.st.toggle_off)
            font.family: root.st.font_family
            font.pixelSize: root.st.font_size - 2
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.show_state
        onClicked: root.toggled()
    }
}
