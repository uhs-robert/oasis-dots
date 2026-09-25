// home/quickshell/.config/quickshell/components/ps1/CodecPortrait.qml
import QtQuick
import Quickshell
import "../../theme"

// An MGS codec portrait: the app icon in a green scanlined frame, with CALL blinking a few times on arrival.
Column {
    id: root

    property var notification: null
    property real size: 40
    // Blinks CALL once through when created; cards for old entries pass false.
    property bool ringing: true

    readonly property string source: !root.notification ? "" : root.notification.image !== "" ? root.notification.image : root.notification.appIcon !== "" ? Quickshell.iconPath(root.notification.appIcon, true) : ""

    spacing: 2

    Rectangle {
        width: root.size
        height: root.size
        color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.green, 0.12))
        border.width: 2
        border.color: Qt.alpha(Theme.green, 0.65)
        clip: true

        Image {
            anchors.fill: parent
            anchors.margins: 3
            source: root.source
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        Text {
            visible: root.source === ""
            anchors.centerIn: parent
            text: "?"
            color: Theme.green
            font.family: Style.font_family
            font.pixelSize: root.size * 0.5
        }

        Repeater {
            model: Math.ceil(root.size / 3)

            Rectangle {
                required property int index
                y: index * 3
                width: root.size
                height: 1
                color: Qt.alpha(Theme.bg_shadow, 0.25)
            }
        }
    }

    Text {
        id: call_text
        anchors.horizontalCenter: parent.horizontalCenter
        text: "CALL"
        color: Theme.green
        font.family: Style.font_family
        font.pixelSize: Math.max(9, Math.round(root.size * 0.3))
        font.bold: true
    }

    SequentialAnimation {
        id: blink
        loops: 4
        NumberAnimation { target: call_text; property: "opacity"; to: 0.1; duration: 220 }
        NumberAnimation { target: call_text; property: "opacity"; to: 1; duration: 220 }
    }

    Component.onCompleted: if (root.ringing) blink.start()
}
