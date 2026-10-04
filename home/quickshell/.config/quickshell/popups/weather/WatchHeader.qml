// home/quickshell/.config/quickshell/popups/weather/WatchHeader.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../lock/skins/goldeneye" as Watch
import "../../theme/Watch.js" as W

// The current conditions as the classic pause watch: warm temperature segments left, blue humidity segments right, a green panel between.
Item {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property int aqi: WeatherState.aq_has_data && WeatherState.aq_current ? WeatherState.aq_current.aqi : -1
    // Temperature fills its eight segments over 0-100 °F in either unit; humidity fills the blue ones.
    readonly property real fahrenheit: !root.has ? 0 : WeatherState.settings.unit === "celsius" ? root.cur.temp * 9 / 5 + 32 : root.cur.temp
    readonly property real health_level: Math.max(0, Math.min(1, root.fahrenheit / 100))
    readonly property real armour_level: root.has ? Math.max(0, Math.min(1, root.cur.humidity / 100)) : 0
    readonly property string digits: root.has ? String(Math.round(root.cur.temp)) : "--"
    readonly property real arc_w: 30
    readonly property real pad: 12

    readonly property var readouts: !root.has ? [] : [
        { label: "HUM", value: root.cur.humidity + "%" },
        { label: "WIND", value: Math.round(root.cur.wind_speed) + " " + WeatherState.wind_dir_label(root.cur.wind_dir) },
        { label: "UV", value: root.cur.uv_index.toFixed(1) },
        { label: "AQI", value: root.aqi >= 0 ? String(root.aqi) : "--" }
    ]

    implicitHeight: Math.round(Math.max(120, Math.min(150, root.width * 0.3)))

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Style.wk.frame
        border.width: 2
        border.color: Style.wk.rim
    }

    Watch.SegmentArc {
        x: 6
        y: 8
        width: root.arc_w
        height: root.height - 16
        thickness: 11
        colors: W.warm
        lit: Math.round(root.health_level * 8)
    }

    Watch.SegmentArc {
        x: root.width - root.arc_w - 6
        y: 8
        width: root.arc_w
        height: root.height - 16
        thickness: 11
        mirror: true
        colors: W.cold_lit
        lit: Math.round(root.armour_level * 8)
    }

    Repeater {
        model: [-1, 1]

        Rectangle {
            required property int modelData
            x: root.width / 2 + modelData * 5 - 2
            y: 2
            width: 4
            height: 6
            color: W.white
        }
    }

    Rectangle {
        x: root.width / 2 - 2.5
        y: root.height - 8
        width: 5
        height: 6
        color: W.white
    }

    Watch.PanelShape {
        id: panel
        x: root.arc_w + 12
        y: 11
        width: root.width - x * 2
        height: root.height - 22
        cut: 12
        notch_w: 6
        notch_h: 18
        top_color: Style.wk.panel_top
        edge: Style.wk.edge
        bottom_color: Style.wk.panel_bottom

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.pad + 4
            anchors.rightMargin: root.pad + 4
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Row {
                    spacing: 4

                    Item {
                        width: ghost.implicitWidth
                        height: ghost.implicitHeight

                        Text {
                            id: ghost
                            anchors.right: parent.right
                            text: "8".repeat(Math.max(2, root.digits.length))
                            color: Qt.alpha(Style.wk.lit, 0.1)
                            font.family: W.digit_font
                            font.pixelSize: Style.font_size * 2 + 4
                        }

                        Text {
                            anchors.right: parent.right
                            text: root.digits
                            color: root.has ? Style.wk.lit : Style.wk.dim
                            font.family: W.digit_font
                            font.pixelSize: Style.font_size * 2 + 4
                        }
                    }

                    Text {
                        text: "°" + WeatherState.unit_symbol()
                        color: Style.wk.mid
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-1)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.topMargin: 2
                    elide: Text.ElideRight
                    text: root.has ? root.cur.cond : WeatherState.loading ? "Loading" : "Unavailable"
                    color: root.has || WeatherState.loading ? Style.wk.mid : Style.pal.error
                    font.family: W.mono_font
                    font.pixelSize: Style.fs(-3)
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1
                }

                Text {
                    visible: root.has
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: "FEELS LIKE " + (root.has ? Math.round(root.cur.feels) + "°" + WeatherState.unit_symbol() : "")
                    color: Style.wk.soft
                    font.family: W.mono_font
                    font.pixelSize: Style.fs(-4)
                }

                Text {
                    visible: WeatherState.stale || WeatherState.failed
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: (WeatherState.failed ? "NO DATA" : "STALE DATA") + (WeatherState.error ? ": " + WeatherState.error : "")
                    color: Style.pal.error
                    font.family: W.mono_font
                    font.pixelSize: Style.fs(-4)
                }
            }

            ColumnLayout {
                visible: root.has && panel.width >= 260
                Layout.preferredWidth: Math.min(160, panel.width * 0.4)
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Repeater {
                    model: root.readouts

                    RowLayout {
                        id: readout_row
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                            text: readout_row.modelData.label
                            color: Style.wk.soft
                            font.family: W.mono_font
                            font.pixelSize: Style.fs(-4)
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            clip: true
                            text: "·".repeat(40)
                            color: Qt.alpha(Style.wk.dim, 0.6)
                            font.family: W.mono_font
                            font.pixelSize: Style.fs(-4)
                        }

                        Text {
                            text: readout_row.modelData.value
                            color: Style.wk.lit
                            font.family: W.mono_font
                            font.pixelSize: Style.fs(-4)
                        }
                    }
                }
            }
        }
    }
}
