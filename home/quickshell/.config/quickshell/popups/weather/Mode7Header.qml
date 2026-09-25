// home/quickshell/.config/quickshell/popups/weather/Mode7Header.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"
import "../../components/snes" as Snes

// A SNES RPG menu window: blue gradient panel in a light double border, conditions set out like a status screen.
Item {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property bool roomy: root.width >= 330
    readonly property var rows: root.has ? [["FEELS", Math.round(root.cur.feels) + "°"], ["HUM", root.cur.humidity + "%"], ["WIND", Math.round(root.cur.wind_speed) + " " + WeatherState.wind_unit().toUpperCase()], ["UV", root.cur.uv_index.toFixed(1)]] : []

    implicitHeight: body.implicitHeight + 24

    Snes.SnesWindow {
        id: menu_window
        anchors.fill: parent
    }

    ColumnLayout {
        id: body
        anchors.left: menu_window.left
        anchors.right: menu_window.right
        anchors.top: menu_window.top
        anchors.leftMargin: 14
        anchors.rightMargin: 14 + menu_window.drop
        anchors.topMargin: 10
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Image {
                visible: root.has
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                Layout.alignment: Qt.AlignVCenter
                readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                source: root.has ? WeatherState.icon_source(root.cur.code, root.cur.is_day) : ""
                sourceSize.width: Math.ceil(80 * dpr)
                sourceSize.height: Math.ceil(80 * dpr)
                smooth: true
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.has ? Math.round(root.cur.temp) + "°" + WeatherState.unit_symbol() : "--°"
                color: root.has ? Theme.fg_strong : Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.font_size * 2
                style: Text.Raised
                styleColor: Style.text_shadow
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: root.has ? root.cur.cond : WeatherState.loading ? "Loading" : "No signal"
                color: root.has || WeatherState.loading ? Theme.theme_secondary : Theme.warning
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
                font.capitalization: Font.AllUppercase
                style: Text.Raised
                styleColor: Style.text_shadow
            }
        }

        GridLayout {
            visible: root.has
            Layout.fillWidth: true
            columns: root.roomy ? 4 : 2
            columnSpacing: 10
            rowSpacing: 3

            Repeater {
                model: root.rows

                Text {
                    id: row_label
                    required property var modelData
                    required property int index
                    Layout.row: Math.floor(row_label.index / (root.roomy ? 2 : 1))
                    Layout.column: 2 * (row_label.index % (root.roomy ? 2 : 1))
                    text: row_label.modelData[0]
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }
            }

            Repeater {
                model: root.rows

                Text {
                    id: row_value
                    required property var modelData
                    required property int index
                    Layout.row: Math.floor(row_value.index / (root.roomy ? 2 : 1))
                    Layout.column: 2 * (row_value.index % (root.roomy ? 2 : 1)) + 1
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: row_value.modelData[1]
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }
            }
        }

        RowLayout {
            visible: WeatherState.location_name !== "" || WeatherState.stale
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: WeatherState.stale ? "STALE" : "LOC"
                color: WeatherState.stale ? Theme.warning : Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
                style: Text.Raised
                styleColor: Style.text_shadow
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: WeatherState.stale ? (WeatherState.error || "Old data") : WeatherState.location_name
                color: WeatherState.stale ? Theme.warning : Theme.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
                style: Text.Raised
                styleColor: Style.text_shadow
            }
        }
    }
}
