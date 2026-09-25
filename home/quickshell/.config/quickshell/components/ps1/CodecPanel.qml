// home/quickshell/.config/quickshell/components/ps1/CodecPanel.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "Codec.js" as Codec

// The MGS codec readout for the live connection: signal as a 140.xx frequency beside the SSID and real percent.
Rectangle {
    id: root

    property string ssid: ""
    property real strength: 0
    property string detail: ""

    implicitHeight: body.implicitHeight + 12
    radius: 3
    color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.green, 0.1))
    border.width: 2
    border.color: Qt.alpha(Theme.green, 0.6)
    clip: true

    Repeater {
        model: Math.ceil(root.height / 3)

        Rectangle {
            required property int index
            y: index * 3
            width: root.width
            height: 1
            color: Qt.alpha(Theme.green, 0.05)
        }
    }

    RowLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 10

        Digits {
            text: Codec.freq(root.strength)
            size: Style.font_size + 2
            color: Theme.green
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 0

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.ssid
                color: Theme.bright_green
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 2
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "SIGNAL " + Math.round(root.strength * 100) + "%" + (root.detail !== "" ? "  " + root.detail : "")
                color: Qt.alpha(Theme.bright_green, 0.75)
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 5
            }
        }
    }
}
