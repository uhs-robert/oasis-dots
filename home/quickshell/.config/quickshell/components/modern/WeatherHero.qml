import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import ".."
import "../../services"

// Current conditions as a large temperature beside the condition, today's low-to-high range bar,
// a row of stat tiles, then the first alert as a tinted card.
ColumnLayout {
    id: root

    signal alert_clicked()

    readonly property bool has_alert: WeatherState.alerts.length > 0
    readonly property var alert: root.has_alert ? WeatherState.alerts[0] : null
    readonly property bool roomy: root.width >= 340
    readonly property var cur: WeatherState.current

    spacing: 12

    component VitalTile: CardSurface {
        id: tile

        property string glyph: ""
        property string label: ""
        property string value: ""
        property string unit: ""
        property string detail: ""
        property color detail_color: Style.text_dim
        // 0-1 draws a mini bar in place of the detail line; -1 keeps the detail.
        property real fill: -1
        property color fill_color: Theme.theme_label
        // Where the wind blows from, in degrees; the arrow points downwind.
        property real wind_from: -1

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
        implicitHeight: tile_column.implicitHeight + 16

        ColumnLayout {
            id: tile_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            spacing: 3

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: tile.glyph + " " + tile.label
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.alignment: Qt.AlignBaseline
                    text: tile.value
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(1)
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }

                Text {
                    Layout.alignment: Qt.AlignBaseline
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: tile.unit
                    color: Style.text_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: detail_text.implicitHeight

                Rectangle {
                    visible: tile.fill >= 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Qt.alpha(Theme.fg_strong, 0.1)

                    Rectangle {
                        width: Math.max(parent.height, parent.width * Math.min(1, tile.fill))
                        height: parent.height
                        radius: parent.radius
                        color: tile.fill_color
                    }
                }

                RowLayout {
                    visible: tile.fill < 0
                    anchors.fill: parent
                    spacing: 3

                    Text {
                        visible: tile.wind_from >= 0
                        text: "\u{f005d}"
                        rotation: tile.wind_from + 180
                        color: Style.text_dim
                        font.family: Theme.font_family
                        font.pixelSize: Style.fs(-4)
                    }

                    Text {
                        id: detail_text
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: tile.detail
                        color: tile.detail_color
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-4)
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 2
        spacing: 16

        Row {
            Layout.alignment: Qt.AlignVCenter

            Text {
                id: temp_text
                text: WeatherState.has_data ? Math.round(WeatherState.current.temp) : "--"
                color: Style.text_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(42)
                font.weight: Font.Medium
                font.letterSpacing: -3
                font.features: { "tnum": 1 }
            }

            Text {
                y: Math.round(temp_text.height * 0.16)
                leftPadding: 2
                text: "°" + WeatherState.unit_symbol()
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(3)
                font.weight: Font.Medium
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Image {
                    visible: WeatherState.has_data
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    Layout.topMargin: -6
                    Layout.bottomMargin: -6
                    Layout.leftMargin: -5
                    Layout.rightMargin: -3
                    readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                    sourceSize.width: Math.ceil(68 * dpr)
                    sourceSize.height: Math.ceil(68 * dpr)
                    source: WeatherState.has_data ? WeatherState.icon_source(WeatherState.current.code, WeatherState.current.is_day) : ""
                    smooth: true
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: WeatherState.cond_text(false)
                    color: WeatherState.has_data || WeatherState.loading ? Style.text_strong : Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(2)
                    font.weight: Font.DemiBold
                }
            }

            Text {
                visible: WeatherState.has_data
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: WeatherState.has_data ? "Feels like " + Math.round(WeatherState.current.feels) + "°" + WeatherState.unit_symbol() : ""
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }

            Text {
                visible: WeatherState.location_name !== "" || WeatherState.stale || WeatherState.failed
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: WeatherState.failed ? WeatherState.error : WeatherState.stale ? WeatherState.stale_text() : WeatherState.location_name
                color: WeatherState.stale || WeatherState.failed ? Theme.warning : Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
            }
        }
    }

    RowLayout {
        visible: WeatherState.has_vitals
        Layout.fillWidth: true
        Layout.leftMargin: 2
        Layout.rightMargin: 2
        spacing: 10

        Text {
            text: Math.round(WeatherState.today_low) + "°"
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }

        Item {
            id: range_track
            Layout.fillWidth: true
            implicitHeight: 10

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 5
                radius: 2.5
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: WeatherState.temp_color(WeatherState.today_low) }
                    GradientStop { position: 1; color: WeatherState.temp_color(WeatherState.today_high) }
                }
            }

            // The ring in the frame colour cuts the dot out of the bar, as Apple Weather's does.
            Rectangle {
                x: Math.max(0, Math.min(range_track.width - width, WeatherState.temp_range_pos * range_track.width - width / 2))
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: 5
                color: Style.text_strong
                border.width: 2
                border.color: Style.frame_color
            }
        }

        Text {
            text: Math.round(WeatherState.today_high) + "°"
            color: Style.text_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
    }

    GridLayout {
        visible: WeatherState.has_vitals
        Layout.fillWidth: true
        columns: root.roomy ? 5 : 3
        columnSpacing: 6
        rowSpacing: 6

        VitalTile {
            glyph: "\u{f058e}"
            label: "HUM"
            value: WeatherState.has_vitals ? root.cur.humidity + "%" : ""
            fill: WeatherState.has_vitals ? root.cur.humidity / 100 : 0
            fill_color: Style.pal.blue
        }

        VitalTile {
            glyph: "\u{f054a}"
            label: "RAIN"
            value: WeatherState.today_pop + "%"
            fill: WeatherState.today_pop / 100
            fill_color: WeatherState.pop_color(WeatherState.today_pop)
        }

        VitalTile {
            glyph: "\u{f059d}"
            label: "WIND"
            value: WeatherState.has_vitals ? String(Math.round(root.cur.wind_speed)) : ""
            unit: WeatherState.wind_unit()
            detail: WeatherState.has_vitals ? WeatherState.compass_label(root.cur.wind_dir) : ""
            wind_from: WeatherState.has_vitals ? root.cur.wind_dir : -1
        }

        VitalTile {
            glyph: "\u{f05a8}"
            label: "UV"
            value: WeatherState.has_vitals ? root.cur.uv_index.toFixed(1) : ""
            detail: WeatherState.has_vitals ? WeatherState.uv_band(root.cur.uv_index).label : ""
            detail_color: WeatherState.has_vitals ? WeatherState.uv_color(root.cur.uv_index) : Style.text_dim
        }

        VitalTile {
            glyph: "\u{f032a}"
            label: "AQI"
            value: WeatherState.aqi_now >= 0 ? String(WeatherState.aqi_now) : "--"
            detail: WeatherState.aqi_now >= 0 ? WeatherState.aqi_band(WeatherState.aqi_now).label : "No data"
            detail_color: WeatherState.aqi_now >= 0 ? WeatherState.aqi_color(WeatherState.aqi_now) : Style.text_muted
        }
    }

    Rectangle {
        visible: root.has_alert
        Layout.fillWidth: true
        implicitHeight: alert_row.implicitHeight + 16
        radius: Style.radius(7)
        border.width: 1
        border.color: Qt.alpha(Theme.theme_label, 0.24)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.tint(Style.frame_shade.a > 0 ? Style.frame_shade : Style.frame_color, Qt.alpha(Theme.theme_label, 0.15)) }
            GradientStop { position: 1; color: Qt.tint(Style.frame_color, Qt.alpha(Theme.theme_label, 0.09)) }
        }

        Sheen {
            color_top: Qt.alpha(Theme.theme_label, 0.3)
            corner: parent.radius
            edge: 1
        }

        RowLayout {
            id: alert_row
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 8
            anchors.rightMargin: 10
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 8
                color: Theme.theme_label

                Text {
                    anchors.centerIn: parent
                    text: "\u{f0026}"
                    color: Theme.bg_crust
                    font.family: Theme.font_family
                    font.pixelSize: 15
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.alert ? root.alert.event + (WeatherState.alerts.length > 1 ? "  +" + (WeatherState.alerts.length - 1) : "") : ""
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-1)
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.alert ? WeatherState.fmt_until(root.alert.ends) : ""
                    color: Style.text_dim
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-4)
                }
            }

            Text {
                text: "\u{f0142}"
                color: Style.text_muted
                font.family: Theme.font_family
                font.pixelSize: 14
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.alert_clicked()
        }
    }
}
