// home/quickshell/.config/quickshell/popups/weather/MemCardHeader.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"

// The PS1 memory card screen: a location strip over the current conditions as the selected save's info panel.
ColumnLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur

    spacing: 6

    Rectangle {
        visible: WeatherState.location_name !== ""
        Layout.fillWidth: true
        Layout.preferredHeight: strip_text.implicitHeight + 6
        radius: 4
        color: "transparent"
        clip: true

        FadeFill {
            radius: parent.radius
            fill: Style.title_bg
        }

        Text {
            id: strip_text
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: WeatherState.location_name.toUpperCase()
            color: Style.title_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
            style: Text.Raised
            styleColor: Style.text_shadow
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: info.implicitHeight + 16
        radius: 6
        color: Qt.alpha(Theme.bg_shadow, 0.35)
        border.width: 2
        border.color: Style.frame_border_color

        RowLayout {
            id: info
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 10

            SaveIcon {
                Layout.alignment: Qt.AlignTop
                size: 44
                code: root.has ? root.cur.code : -1
                is_day: root.has ? root.cur.is_day : true
                lit: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: root.has ? Math.round(root.cur.temp) + "°" + WeatherState.unit_symbol() : "--°"
                        color: root.has ? Style.text_strong : Style.text_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(12)
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
                            text: root.has ? root.cur.cond.toUpperCase() : WeatherState.loading ? "LOADING" : "NO DATA"
                            color: root.has || WeatherState.loading ? Theme.theme_primary_light : Theme.warning
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                        }

                        Text {
                            visible: root.has
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "FEELS " + (root.has ? Math.round(root.cur.feels) + "°" : "")
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-5)
                        }
                    }
                }

                Flow {
                    visible: root.has
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: root.has ? [["HUM", root.cur.humidity + "%"], ["WIND", Math.round(root.cur.wind_speed) + " " + WeatherState.wind_unit().toUpperCase()], ["UV", root.cur.uv_index.toFixed(1)]] : []

                        Row {
                            required property var modelData
                            spacing: 4

                            Text {
                                text: parent.modelData[0]
                                color: Theme.theme_primary_light
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-5)
                            }

                            Text {
                                text: parent.modelData[1]
                                color: Style.text_fg
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
                    text: "STALE DATA" + (WeatherState.error ? ": " + WeatherState.error : "")
                    color: Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                }
            }
        }
    }
}
