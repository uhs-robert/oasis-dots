// home/quickshell/.config/quickshell/popups/weather/DexHeader.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
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
    readonly property int stat_px: Style.font_size - 4
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
                fill: Style.shade_0
                rings: [Style.shade_2, Style.shade_0, Style.shade_3]
            }

            Image {
                anchors.fill: parent
                anchors.margins: 6
                fillMode: Image.Tile
                smooth: false
                source: "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'><rect width='1' height='1' fill='" + Style.shade_1 + "'/></svg>")
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
                color: Style.shade_2
                font.family: Style.title_font_family
                font.pixelSize: 8
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.name
                color: root.has || WeatherState.loading ? Style.shade_3 : Theme.warning
                font.family: Style.title_font_family
                font.pixelSize: name_metrics.advanceWidth(root.name) <= root.width - root.box - 12 ? 16 : 8
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.preferredHeight: 2
                color: Style.shade_2
            }

            GridLayout {
                visible: root.has
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 10
                rowSpacing: 1

                Text {
                    text: "TEMP"
                    color: Style.shade_2
                    font.family: Style.font_family
                    font.pixelSize: root.stat_px
                }

                Row {
                    spacing: 6

                    PixelTemp {
                        value: root.has ? root.cur.temp : 0
                        unit: WeatherState.unit_symbol()
                        color: Style.shade_3
                        font_size: root.stat_px
                    }

                    Text {
                        visible: root.roomy
                        text: "feels"
                        color: Style.shade_3
                        font.family: Style.font_family
                        font.pixelSize: root.stat_px
                    }

                    PixelTemp {
                        visible: root.roomy
                        value: root.has ? root.cur.feels : 0
                        unit: WeatherState.unit_symbol()
                        color: Style.shade_3
                        font_size: root.stat_px
                    }
                }

                Text {
                    text: "HUM"
                    color: Style.shade_2
                    font.family: Style.font_family
                    font.pixelSize: root.stat_px
                }

                Text {
                    text: root.has ? root.cur.humidity + "%" : ""
                    color: Style.shade_3
                    font.family: Style.font_family
                    font.pixelSize: root.stat_px
                }

                Text {
                    text: "WIND"
                    color: Style.shade_2
                    font.family: Style.font_family
                    font.pixelSize: root.stat_px
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.has ? Math.round(root.cur.wind_speed) + " " + WeatherState.wind_unit() + " " + WeatherState.wind_dir_label(root.cur.wind_dir) : ""
                    color: Style.shade_3
                    font.family: Style.font_family
                    font.pixelSize: root.stat_px
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

    TextBox {
        id: description
        Layout.fillWidth: true
        text: root.entry
    }
}
