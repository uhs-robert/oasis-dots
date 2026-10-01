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
    readonly property real k: panel.height / 485

    implicitHeight: root.dial

    SystemClock {
        id: clock
        enabled: root.running
        precision: root.live ? SystemClock.Seconds : SystemClock.Minutes
    }

    Item {
        id: face
        width: root.dial
        height: root.dial

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: W.black
            border.width: 2
            border.color: W.rim
        }

        Watch.SegmentArc {
            x: 6
            y: (root.dial - height) / 2
            width: 24
            height: 90
            thickness: 8
            gap: 3
            colors: W.warm
        }

        Watch.SegmentArc {
            x: root.dial - 6 - width
            y: (root.dial - height) / 2
            width: 24
            height: 90
            thickness: 8
            gap: 3
            mirror: true
            colors: W.cold_lit
        }

        Repeater {
            model: [-4, 4]

            Rectangle {
                required property int modelData
                x: root.dial / 2 + modelData - 2
                y: 5
                width: 4
                height: 9
                color: W.white
            }
        }

        Rectangle {
            x: root.dial / 2 - 2
            y: root.dial - 14
            width: 4
            height: 9
            color: W.white
        }

        Repeater {
            model: [[-1, -1], [1, -1], [-1, 1], [1, 1]]

            Rectangle {
                required property var modelData
                x: root.dial / 2 + modelData[0] * 27 - 3
                y: root.dial / 2 + modelData[1] * 40 - 3
                width: 6
                height: 6
                radius: 3
                color: W.white
            }
        }

        Watch.PanelShape {
            id: panel
            anchors.centerIn: parent
            width: root.dial * 0.5
            height: width
            cut: 9
            notches: false
            clip: true

            Watch.WatchHands {
                x: panel.width / 2 - 510 * root.k
                y: panel.height / 2 - 360 * root.k
                scale: root.k
                transformOrigin: Item.TopLeft
                now: clock.date
                show_seconds: root.live
            }
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
