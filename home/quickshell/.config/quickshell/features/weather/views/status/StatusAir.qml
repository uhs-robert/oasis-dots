pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.ui.effects
import qs.ui.menu
import qs.theme
import qs.ui.gauges
import qs.features.clock
import qs.features.weather

// Air as the FF7 status screen: the AQI as the headline stat with the band's status effects beside it, pollutants as
// stat rows on ATB bars, and the next 24 hours as ATB gauges with the white glove over the cursor hour (h/l move it).
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]
    readonly property var cur: WeatherState.aq_current
    readonly property bool ready: WeatherState.aq_has_data && !!root.cur
    readonly property color aqi_tint: root.cur ? WeatherState.aqi_color(root.cur.aqi) : Style.text_dim

    readonly property int legend_h: 20
    readonly property int top_pad: 22
    readonly property int bottom_pad: 18
    // Where a bar is full, per pollutant: roughly the start of the "Unhealthy" band, in ug/m3.
    readonly property var pollutants: root.cur ? [
        { label: "PM2.5", value: root.cur.pm25, full: 150 },
        { label: "PM10", value: root.cur.pm10, full: 250 },
        { label: "OZONE", value: root.cur.ozone, full: 200 }
    ] : []

    readonly property var effects: ({
        regen: { name: "Regen", color: Style.pal.green },
        sadness: { name: "Sadness", color: Style.pal.info },
        poison: { name: "Poison", color: Style.pal.magenta },
        slow: { name: "Slow", color: Style.pal.cyan },
        doom: { name: "D.Sentence", color: Style.pal.error }
    })
    // Indexed like WeatherState.aqi_bands: the worse the air, the more of FF7's ailments pile on.
    readonly property var band_effects: [["regen"], ["sadness"], ["poison"], ["poison", "slow"], ["poison", "slow", "sadness"], ["poison", "slow", "sadness", "doom"]]
    readonly property var cur_effects: root.cur ? root.band_effects[WeatherState.aqi_bands.indexOf(WeatherState.aqi_band(root.cur.aqi))].map(k => root.effects[k]) : []

    function lit(color) {
        return Qt.tint(color, Qt.alpha(Theme.fg_strong, 0.55));
    }

    function request_paint() {
        canvas.requestPaint();
    }

    component Label: Text {
        color: Theme.theme_primary_light
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        font.weight: Font.ExtraBold
        font.letterSpacing: 1
    }

    // The glyph of a status effect: a small orb in its colour followed by its name, in a dark capsule like the menu's status column.
    component EffectChip: Rectangle {
        id: chip
        property var effect

        implicitWidth: chip_row.implicitWidth + 12
        implicitHeight: chip_row.implicitHeight + 6
        radius: height / 2
        color: Qt.alpha(Theme.bg_crust, 0.55)
        border.width: 1
        border.color: Qt.alpha(chip.effect.color, 0.7)

        Row {
            id: chip_row
            anchors.centerIn: parent
            spacing: 5

            MateriaOrb {
                anchors.verticalCenter: parent.verticalCenter
                width: 9
                height: 9
                color: chip.effect.color
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.effect.name
                color: Theme.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
                font.weight: Font.ExtraBold
            }
        }
    }

    FontMetrics {
        id: label_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        font.weight: Font.ExtraBold
        font.letterSpacing: 1
    }

    readonly property real label_col_w: Math.max(44, label_metrics.advanceWidth("PM2.5") + 8)

    StatusWindow {
        anchors.fill: parent
        visible: !root.ready
    }

    Text {
        anchors.centerIn: parent
        visible: !root.ready
        text: WeatherState.aq_loading ? "Loading..." : "Air quality unavailable"
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: Style.font_size
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        visible: root.ready

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: status_body.implicitHeight + 14

            StatusWindow {
                anchors.fill: parent
            }

            ColumnLayout {
                id: status_body
                anchors.fill: parent
                anchors.margins: 7
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 5

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MateriaOrb {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        color: root.aqi_tint
                    }

                    Label {
                        text: "AQI"
                    }

                    Text {
                        text: root.cur ? root.cur.aqi : "--"
                        color: root.lit(root.aqi_tint)
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(10)
                        font.weight: Font.ExtraBold
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: root.cur ? WeatherState.aqi_band(root.cur.aqi).label : ""
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-1)
                        font.weight: Font.ExtraBold
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.cur_effects

                        EffectChip {
                            required property var modelData
                            effect: modelData
                        }
                    }
                }

                Repeater {
                    model: root.pollutants

                    RowLayout {
                        id: stat
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6

                        Label {
                            Layout.preferredWidth: root.label_col_w
                            text: stat.modelData.label
                        }

                        AtbBar {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 6
                            value: stat.modelData.value / stat.modelData.full
                            fill_color: Style.pal.primary_strong
                            shade_color: Style.pal.primary_light
                            horizontal: true
                        }

                        Text {
                            Layout.preferredWidth: root.label_col_w
                            horizontalAlignment: Text.AlignRight
                            text: stat.modelData.value.toFixed(1)
                            color: Theme.fg_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-2)
                            font.weight: Font.ExtraBold
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StatusWindow {
                anchors.fill: parent
            }

            RowLayout {
                x: 12
                y: 5
                width: parent.width - 24
                height: root.legend_h
                spacing: 8

                MateriaOrb {
                    Layout.preferredWidth: 11
                    Layout.preferredHeight: 11
                    color: root.cursor_row ? WeatherState.aqi_color(root.cursor_row.aqi) : root.aqi_tint
                }

                Label {
                    text: "24H"
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    visible: !!root.cursor_row
                    elide: Text.ElideRight
                    Layout.maximumWidth: parent.width - 70
                    readonly property var r: root.cursor_row
                    text: r ? WeatherState.format_hour(new Date(r.dt)) + "  AQI " + r.aqi + "  " + WeatherState.aqi_band(r.aqi).label : ""
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                    font.weight: Font.ExtraBold
                }
            }

            Canvas {
                id: canvas
                x: 6
                y: root.legend_h + 6
                width: parent.width - 12
                height: parent.height - root.legend_h - 12

                readonly property int count: Math.max(1, root.slice.length)
                readonly property real col_w: canvas.width / canvas.count
                readonly property real gauge_w: Math.max(6, Math.min(18, canvas.col_w - 4))
                readonly property real gauge_h: canvas.height - root.top_pad - root.bottom_pad
                readonly property real max_v: Math.max(100, ...root.slice.map(r => r.aqi))

                function x_of(i) {
                    return canvas.col_w * (i + 0.5);
                }

                function fill_top(aqi) {
                    return root.top_pad + canvas.gauge_h * (1 - Math.min(1, aqi / canvas.max_v));
                }

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const rows = root.slice;
                    if (rows.length === 0) return;
                    const bottom = root.top_pad + canvas.gauge_h;

                    ctx.font = "800 " + Style.fs(-4) + "px \"" + Style.font_family + "\"";
                    ctx.textAlign = "center";
                    const label_w = ctx.measureText(WeatherState.format_hour(new Date(2000, 0, 1, 12))).width + 18;
                    const step = [3, 4, 6, 8, 12].find(n => n * canvas.col_w >= label_w) || 12;

                    for (let i = 0; i < rows.length; i++) {
                        const x = canvas.x_of(i) - canvas.gauge_w / 2;
                        const selected = i === root.cursor_index;
                        if (selected) {
                            ctx.fillStyle = Qt.alpha(Theme.fg_strong, 0.08);
                            ctx.fillRect(i * canvas.col_w, 0, canvas.col_w, canvas.height);
                        }

                        const color = WeatherState.aqi_color(rows[i].aqi);
                        ctx.fillStyle = Theme.bg_crust;
                        ctx.fillRect(x, root.top_pad, canvas.gauge_w, canvas.gauge_h);
                        const fill_h = Math.round((canvas.gauge_h - 2) * Math.min(1, rows[i].aqi / canvas.max_v));
                        if (fill_h > 0) {
                            const grad = ctx.createLinearGradient(0, bottom - 1 - fill_h, 0, bottom - 1);
                            grad.addColorStop(0, root.lit(color));
                            grad.addColorStop(1, color);
                            ctx.fillStyle = grad;
                            ctx.fillRect(x + 1, bottom - 1 - fill_h, canvas.gauge_w - 2, fill_h);
                            ctx.fillStyle = Theme.bg_crust;
                            ctx.globalAlpha = 0.35;
                            for (let y = bottom - 7; y > bottom - 1 - fill_h; y -= 6) ctx.fillRect(x + 1, y, canvas.gauge_w - 2, 1);
                            ctx.globalAlpha = 1;
                        }
                        ctx.strokeStyle = selected ? Theme.fg_strong : Theme.fg_muted;
                        ctx.lineWidth = 1;
                        ctx.strokeRect(x + 0.5, root.top_pad + 0.5, canvas.gauge_w - 1, canvas.gauge_h - 1);

                        if (i % step === 0) {
                            ctx.fillStyle = selected ? Theme.fg_strong : Style.text_dim;
                            ctx.fillText(WeatherState.format_hour(new Date(rows[i].dt)), Math.max(label_w / 2, canvas.x_of(i)), canvas.height - 4);
                        }
                    }
                }

                Connections {
                    target: root
                    function onSliceChanged() { canvas.requestPaint(); }
                    function onCursor_indexChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onFont_familyChanged() { canvas.requestPaint(); }
                    function onFont_sizeChanged() { canvas.requestPaint(); }
                    function onPalChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: TimeFormat
                    function onH24Changed() { canvas.requestPaint(); }
                }
                Connections {
                    target: Theme
                    function onBg_crustChanged() { canvas.requestPaint(); }
                    function onFg_strongChanged() { canvas.requestPaint(); }
                }

                HandCursor {
                    visible: !!root.cursor_row
                    width: 18
                    height: 11
                    // Rotated about its centre to point down at the gauge, in the room above the bars.
                    rotation: 90
                    x: canvas.x_of(root.cursor_index) - width / 2
                    y: root.top_pad - 5 - height / 2 - width / 2 + 2
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mouse => {
                        if (root.slice.length === 0) return;
                        root.on_select(Math.max(0, Math.min(root.slice.length - 1, Math.floor(mouse.x / canvas.col_w))));
                    }
                }
            }
        }
    }
}
