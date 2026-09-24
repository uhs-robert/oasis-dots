// home/quickshell/.config/quickshell/popups/weather/WsHeader.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

// WeatherStar 4000 "Current Conditions": a yellow title over a bevelled blue panel of readings.
ColumnLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property bool roomy: root.width >= 330
    readonly property int row_px: Style.font_size - 4
    readonly property var rows: !root.has ? [] : [
        ["Humidity:", root.cur.humidity + "%"],
        ["Dewpoint:", Math.round(root.cur.dew_point) + "°"]
    ].concat(root.roomy ? [["Feels Like:", Math.round(root.cur.feels) + "°"]] : [], [
        ["Wind:", WeatherState.wind_dir_label(root.cur.wind_dir) + " " + Math.round(root.cur.wind_speed) + " " + WeatherState.wind_unit()]
    ], root.roomy ? [["Pressure:", WeatherState.pressure_display(root.cur.pressure)]] : [])

    spacing: 4

    Text {
        text: "Current Conditions"
        color: Theme.theme_secondary
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 1
        style: Text.Outline
        styleColor: Theme.bg_shadow
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: grid.implicitHeight + 16

        WsPanel {
            anchors.fill: parent
        }

        GridLayout {
            id: grid
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            columns: root.roomy ? 2 : 1
            columnSpacing: 14
            rowSpacing: 2

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: !root.roomy
                spacing: 0

                RowLayout {
                    spacing: 8

                    Text {
                        text: root.has ? Math.round(root.cur.temp) + "°" : "--"
                        color: root.has ? Theme.fg_strong : Style.text_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size * 2
                        style: Text.Outline
                        styleColor: Theme.bg_shadow
                    }

                    Image {
                        visible: root.has
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                        sourceSize.width: Math.ceil(88 * dpr)
                        sourceSize.height: Math.ceil(88 * dpr)
                        source: root.has ? WeatherState.icon_source(root.cur.code, root.cur.is_day) : ""
                        smooth: true
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: root.roomy ? Math.max(120, root.width * 0.42) : -1
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.has ? root.cur.cond : WeatherState.loading ? "Loading..." : "No Report Available"
                    color: root.has || WeatherState.loading ? Theme.fg_strong : Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: root.row_px
                    style: Text.Outline
                    styleColor: Theme.bg_shadow
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignTop
                spacing: 0

                Text {
                    visible: WeatherState.location_name !== ""
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: WeatherState.location_name.split(",")[0]
                    color: Theme.theme_secondary
                    font.family: Style.font_family
                    font.pixelSize: root.row_px
                    style: Text.Outline
                    styleColor: Theme.bg_shadow
                }

                Repeater {
                    model: root.rows

                    RowLayout {
                        id: reading
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: reading.modelData[0]
                            color: Theme.fg_strong
                            font.family: Style.font_family
                            font.pixelSize: root.row_px
                            style: Text.Outline
                            styleColor: Theme.bg_shadow
                        }

                        Text {
                            text: reading.modelData[1]
                            color: Theme.fg_strong
                            font.family: Style.font_family
                            font.pixelSize: root.row_px
                            style: Text.Outline
                            styleColor: Theme.bg_shadow
                        }
                    }
                }

                Text {
                    visible: WeatherState.stale || (!root.has && !WeatherState.loading && WeatherState.error !== "")
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: (WeatherState.stale ? "Stale Data" : "Error") + (WeatherState.error ? ": " + WeatherState.error : "")
                    color: Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: root.row_px - 2
                }
            }
        }
    }
}
