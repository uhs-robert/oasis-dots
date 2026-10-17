import QtQuick
import QtQuick.Layouts
import qs.components
import qs.ui.effects
import qs.theme
import qs.services
import "PixelArt.js" as PixelArt

// A Pokédex entry for the current weather: dot-matrix sprite, No. (WMO code), name, stats and a typed-out description.
ColumnLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property var today: WeatherState.days.length > 0 ? WeatherState.days[0] : null
    readonly property bool roomy: root.width >= 320
    readonly property int sprite_pixel: root.roomy ? 3 : 2
    readonly property int box: root.roomy ? 64 : 48
    readonly property int stat_px: Style.fs(-4)
    readonly property string place: WeatherState.location_name.split(",")[0].trim()
    readonly property string name: root.has ? root.cur.cond.toUpperCase() : WeatherState.loading ? "LOADING" : "NO DATA"
    readonly property bool open: Popups.open_name === "weather"

    readonly property var flavour: ({
        clear: "The sky is clear over ",
        night: "Stars shine over ",
        partly: "Clouds drift over ",
        partly_night: "Clouds drift over ",
        cloud: "Clouds blanket the sky over ",
        fog: "A thick fog hides ",
        drizzle: "A light drizzle falls on ",
        rain: "Rain falls on ",
        snow: "Snow falls on ",
        storm: "Thunder rumbles over "
    })
    readonly property string entry: !root.has ? (WeatherState.error !== "" ? "No signal. " + WeatherState.error : "Searching the skies...")
        : root.flavour[PixelArt.kind(root.cur.code, root.cur.is_day)] + (root.place !== "" ? root.place : "the area") + "." + (root.today ? " " + root.today.pop + "% chance of rain today." : "")

    readonly property var readouts: WeatherState.vitals.filter(v => ["feels", "wind", "uv", "aqi"].indexOf(v.key) >= 0)

    // The EPA's own short name keeps the longest AQI band on one line.
    function readout_text(vital) {
        const detail = vital.detail.replace("Unhealthy for Sensitive Groups", "USG");
        return [vital.value, vital.unit, detail].filter(part => part !== "").join(" ").toUpperCase();
    }

    onOpenChanged: if (root.open) description.type_out()

    spacing: 10

    FontMetrics {
        id: name_metrics
        font.family: Style.title_font_family
        font.pixelSize: 16
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Item {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: root.box
            Layout.preferredHeight: root.box

            PixelBox {
                anchors.fill: parent
                fill: Style.pixel_shades[0]
                rings: [Style.pixel_shades[2], Style.pixel_shades[0], Style.pixel_shades[3]]
            }

            Image {
                anchors.fill: parent
                anchors.margins: 6
                fillMode: Image.Tile
                smooth: false
                source: "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'><rect width='1' height='1' fill='" + Style.pixel_shades[1] + "'/></svg>")
            }

            PixelSprite {
                visible: root.has
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
                pixel: root.sprite_pixel
                rows: root.has ? PixelArt.sprite(root.cur.code, root.cur.is_day) : []
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
            spacing: 4

            Text {
                text: "No." + (root.has ? String(root.cur.code).padStart(3, "0") : "---")
                color: Style.pixel_shades[2]
                font.family: Style.title_font_family
                font.pixelSize: 8
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.name
                color: root.has || WeatherState.loading ? Style.pixel_shades[3] : Theme.warning
                font.family: Style.title_font_family
                font.pixelSize: name_metrics.advanceWidth(root.name) <= root.width - root.box - 12 ? 16 : 8
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.preferredHeight: 2
                color: Style.pixel_shades[2]
            }

            GridLayout {
                visible: WeatherState.has_vitals
                Layout.fillWidth: true
                columns: root.roomy ? 4 : 2
                columnSpacing: 10
                rowSpacing: 1

                Repeater {
                    model: root.readouts

                    Text {
                        id: readout_label
                        required property var modelData
                        required property int index
                        Layout.row: Math.floor(readout_label.index / (root.roomy ? 2 : 1))
                        Layout.column: 2 * (readout_label.index % (root.roomy ? 2 : 1))
                        text: readout_label.modelData.label
                        color: Style.pixel_shades[2]
                        font.family: Style.font_family
                        font.pixelSize: root.stat_px
                    }
                }

                Repeater {
                    model: root.readouts

                    Item {
                        id: readout_value
                        required property var modelData
                        required property int index
                        readonly property bool shows_degrees: readout_value.modelData.key === "feels"
                        Layout.row: Math.floor(readout_value.index / (root.roomy ? 2 : 1))
                        Layout.column: 2 * (readout_value.index % (root.roomy ? 2 : 1)) + 1
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitWidth: readout_value.shows_degrees ? readout_temp.implicitWidth : readout_text.implicitWidth
                        implicitHeight: readout_text.implicitHeight

                        PixelTemp {
                            id: readout_temp
                            visible: readout_value.shows_degrees
                            value: Number(readout_value.modelData.value)
                            unit: WeatherState.unit_symbol()
                            color: Style.pixel_shades[3]
                            font_size: root.stat_px
                        }

                        Text {
                            id: readout_text
                            visible: !readout_value.shows_degrees
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.readout_text(readout_value.modelData)
                            color: Style.pixel_shades[3]
                            font.family: Style.font_family
                            font.pixelSize: root.stat_px
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
                font.pixelSize: root.stat_px
            }
        }
    }

    // Base stats: TEMP spans today's low to high with now as the bright segment; HUM and RAIN fill from empty.
    GridLayout {
        visible: WeatherState.has_vitals
        Layout.fillWidth: true
        columns: 5
        columnSpacing: 8
        rowSpacing: 4

        Text {
            text: "TEMP"
            color: Style.pixel_shades[2]
            font.family: Style.font_family
            font.pixelSize: root.stat_px
        }

        PixelTemp {
            value: WeatherState.has_vitals ? WeatherState.current.temp : 0
            unit: WeatherState.unit_symbol()
            color: Style.pixel_shades[3]
            font_size: root.stat_px
        }

        PixelTemp {
            value: WeatherState.today_low
            color: Style.pixel_shades[2]
            font_size: root.stat_px
        }

        DexStatBar {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            range: true
            value: WeatherState.temp_range_pos
        }

        PixelTemp {
            value: WeatherState.today_high
            color: Style.pixel_shades[2]
            font_size: root.stat_px
        }

        Text {
            text: "HUM"
            color: Style.pixel_shades[2]
            font.family: Style.font_family
            font.pixelSize: root.stat_px
        }

        Text {
            text: WeatherState.has_vitals ? WeatherState.current.humidity + "%" : ""
            color: Style.pixel_shades[3]
            font.family: Style.font_family
            font.pixelSize: root.stat_px
        }

        DexStatBar {
            Layout.columnSpan: 3
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            value: WeatherState.has_vitals ? WeatherState.current.humidity / 100 : 0
        }

        Text {
            text: "RAIN"
            color: Style.pixel_shades[2]
            font.family: Style.font_family
            font.pixelSize: root.stat_px
        }

        Text {
            text: WeatherState.today_pop + "%"
            color: Style.pixel_shades[3]
            font.family: Style.font_family
            font.pixelSize: root.stat_px
        }

        DexStatBar {
            Layout.columnSpan: 3
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            value: WeatherState.today_pop / 100
        }
    }

    TextBox {
        id: description
        Layout.fillWidth: true
        text: root.entry
    }
}
