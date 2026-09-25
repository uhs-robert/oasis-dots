// home/quickshell/.config/quickshell/components/ps1/SaveClock.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

// Today as the selected save's info panel: a lit calendar save block beside the time, date and week.
Rectangle {
    id: root

    property bool running: false
    property int week: 0
    readonly property date now: Timezones.shift(clock.date)
    readonly property string zone: Timezones.abbrevs[Timezones.index] || ""

    implicitHeight: info.implicitHeight + 16
    radius: 6
    color: Qt.alpha(Theme.bg_shadow, 0.35)
    border.width: 2
    border.color: Style.frame_border_color

    SystemClock {
        id: clock
        enabled: root.running
        precision: SystemClock.Minutes
    }

    RowLayout {
        id: info
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 44
            implicitHeight: 44
            radius: 3
            color: Style.selection_bg
            border.width: 2
            border.color: Theme.theme_primary_light

            // 16px pixel calendar drawn at 2x.
            Item {
                anchors.centerIn: parent
                width: 32
                height: 32

                Repeater {
                    model: {
                        const rects = [[2, 15, 14, 1, Theme.bg_shadow], [15, 4, 1, 11, Theme.bg_shadow], [1, 3, 14, 12, Theme.fg_strong], [1, 3, 14, 3, Theme.theme_label], [4, 1, 1, 4, Theme.fg_dim], [11, 1, 1, 4, Theme.fg_dim]];
                        for (const x of [3, 6, 9, 12])
                            for (const y of [8, 11])
                                rects.push([x, y, 2, 2, x === 9 && y === 11 ? Theme.theme_primary_strong : Theme.fg_dim]);
                        return rects;
                    }

                    Rectangle {
                        required property var modelData
                        x: modelData[0] * 2
                        y: modelData[1] * 2
                        width: modelData[2] * 2
                        height: modelData[3] * 2
                        color: modelData[4]
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "TODAY"
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - 5
                    font.letterSpacing: 1
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Qt.alpha(Theme.theme_primary_light, 0.3)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: Qt.formatTime(root.now, "HH:mm")
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size + 12
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Qt.formatDate(root.now, "ddd d MMM yyyy").toUpperCase()
                        color: Theme.theme_primary_light
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size - 3
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "WEEK " + root.week + (root.zone ? " · " + root.zone.toUpperCase() : "")
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size - 5
                    }
                }
            }
        }
    }
}
