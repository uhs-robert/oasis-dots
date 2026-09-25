// home/quickshell/.config/quickshell/popups/weather/BattleHeader.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// A Dragon Quest encounter: the condition appears as the enemy, with its stats in the status line.
Item {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property int sprite: root.width >= 300 ? 48 : 32
    readonly property var stats: root.has ? [["TEMP", Math.round(root.cur.temp) + "°"], ["HUM", root.cur.humidity + "%"], ["FEEL", Math.round(root.cur.feels) + "°"], ["WIND", Math.round(root.cur.wind_speed)]] : []

    implicitHeight: body.implicitHeight + 30

    DqWindow {
        anchors.fill: parent
        anchors.topMargin: 6
        title: WeatherState.location_name.toUpperCase()

        RowLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            Image {
                visible: root.has
                Layout.preferredWidth: root.sprite
                Layout.preferredHeight: root.sprite
                Layout.alignment: Qt.AlignVCenter
                sourceSize.width: 16
                sourceSize.height: 16
                source: root.has ? WeatherState.icon_source(root.cur.code, root.cur.is_day) : ""
                smooth: false
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.has ? root.cur.cond.toUpperCase() + " APPEARS!" : WeatherState.loading ? "LOADING..." : "NOTHING APPEARS."
                    color: root.has || WeatherState.loading ? Theme.fg_strong : Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                    lineHeight: 1.3
                }

                Flow {
                    visible: root.has
                    Layout.fillWidth: true
                    spacing: 12

                    Repeater {
                        model: root.stats

                        Row {
                            required property var modelData
                            spacing: 5

                            Text {
                                text: parent.modelData[0]
                                color: Style.caret_color
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-5)
                            }

                            Text {
                                text: parent.modelData[1]
                                color: Theme.fg_strong
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-5)
                            }
                        }
                    }
                }

                Text {
                    visible: WeatherState.stale
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: "STALE DATA"
                    color: Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                }
            }
        }
    }
}
