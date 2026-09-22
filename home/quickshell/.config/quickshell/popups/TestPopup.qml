// home/quickshell/.config/quickshell/popups/TestPopup.qml
import QtQuick
import "../components"
import "../theme"

Popup {
    id: root

    popup_name: "test"
    implicitWidth: 200
    implicitHeight: 80

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.bg_core

        Text {
            anchors.centerIn: parent
            text: "test popup"
            color: Theme.fg_core
            font.family: Theme.font_family
            font.pixelSize: Theme.font_size
        }
    }
}
