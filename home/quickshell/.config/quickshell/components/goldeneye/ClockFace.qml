// home/quickshell/.config/quickshell/components/goldeneye/ClockFace.qml
import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "../../lock/skins/goldeneye" as Watch
import "../../lock/skins/goldeneye/Watch.js" as W

// An analogue clock in the watch's dress: a round black dial, white bars and studs, a green panel and the pale hands, with the time in seven-segment digits beside it.
// The seconds hand ticks on the wall-clock second only while `running` on AC; otherwise the face shows the minute.
Item {
    id: root

    property bool running: false
    readonly property bool live: root.running && Power.on_ac
    readonly property real dial: 112
    readonly property real k: panel.height / 485

    implicitHeight: root.dial

    SystemClock {
        id: clock
        enabled: root.running
        precision: root.live ? SystemClock.Seconds : SystemClock.Minutes
    }

    Row {
        anchors.centerIn: parent
        spacing: 22

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

            Repeater {
                model: [0, 90, 180, 270]

                Item {
                    id: tick
                    required property int modelData
                    anchors.centerIn: parent
                    width: 1
                    height: 1
                    rotation: tick.modelData

                    Repeater {
                        model: tick.modelData === 0 ? [-4, 4] : [0]

                        Rectangle {
                            required property int modelData
                            x: modelData - 2
                            y: -root.dial / 2 + 4
                            width: 4
                            height: 9
                            color: W.white
                        }
                    }
                }
            }

            Repeater {
                model: [45, 135, 225, 315]

                Item {
                    id: stud
                    required property int modelData
                    anchors.centerIn: parent
                    width: 1
                    height: 1
                    rotation: stud.modelData

                    Rectangle {
                        x: -3.5
                        y: -root.dial / 2 + 6
                        width: 7
                        height: 7
                        radius: 3.5
                        color: W.white
                    }
                }
            }

            Watch.PanelShape {
                id: panel
                anchors.centerIn: parent
                width: root.dial * 0.6
                height: width
                cut: 10
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
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatTime(clock.date, "HH:mm")
            color: W.green
            font.family: W.digit_font
            font.pixelSize: 30
        }
    }
}
