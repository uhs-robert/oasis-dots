// home/quickshell/.config/quickshell/components/goldeneye/ClockFace.qml
import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "../../lock/skins/goldeneye" as Watch
import "../../lock/skins/goldeneye/Watch.js" as W

// An analogue clock in the watch's dress: a round black dial with the bezel arcs, white bars and studs, a green panel and the pale hands, and the time in seven-segment digits beside it.
// The seconds hand ticks on the wall-clock second only while `running` on AC; otherwise the face shows the minute.
Item {
    id: root

    property bool running: false
    readonly property bool live: root.running && Power.on_ac
    readonly property real dial: 124
    readonly property real k: face.panel_item.height / 485

    implicitHeight: root.dial

    SystemClock {
        id: clock
        enabled: root.running
        precision: root.live ? SystemClock.Seconds : SystemClock.Minutes
    }

    DialFace {
        id: face
        width: root.dial

        Watch.WatchHands {
            x: face.panel_item.width / 2 - 510 * root.k
            y: face.panel_item.height / 2 - 360 * root.k
            scale: root.k
            transformOrigin: Item.TopLeft
            now: clock.date
            show_seconds: root.live
        }
    }

    Text {
        anchors.left: face.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: Qt.formatTime(clock.date, "HH:mm")
        color: W.green
        font.family: W.digit_font
        font.pixelSize: 60
        fontSizeMode: Text.Fit
        minimumPixelSize: 24
    }
}
