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
    // Bracketed styles pad the row like a list row; the default stays flush.
    readonly property real pad: Style.toggle_brackets ? 6 : 0

    signal toggled()

    key: root.show_state ? "t" : ""
    Layout.fillWidth: true
    implicitHeight: Style.toggle_brackets ? Style.px(22) : content_row.implicitHeight

    RowLayout {
        id: content_row
        anchors.fill: parent
        anchors.leftMargin: root.pad + root.inset
        anchors.rightMargin: root.pad + root.key_space
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: root.label
            color: root.fg(Theme.fg_strong)
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 1
        }

        Text {
            visible: root.show_state
            text: Style.toggle_brackets ? (root.checked ? "[ ON ]" : "[OFF]") : (root.checked ? "On" : "Off")
            color: root.fg(root.checked ? Style.toggle_on : Style.toggle_off)
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 2
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.show_state
        onClicked: root.toggled()
    }
}
