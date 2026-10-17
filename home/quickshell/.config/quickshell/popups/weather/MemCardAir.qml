import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.features.clock

// Hourly's Air sub-view as a memory card: the 24 hours as save blocks filled to their AQI and coloured by category,
// the selected hour's save title above, and the pollutants as block gauges in a BIOS panel. h/l move the hour cursor.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]
    readonly property var current: WeatherState.aq_current
    readonly property bool ready: WeatherState.aq_has_data && !!root.current

    readonly property int card_blocks: 12
    readonly property int block_gap: 2
    // The chart tops out at AQI 100 so a clean day still reads as a low card, and grows only for worse air.
    readonly property real full_scale: Math.max(100, ...root.slice.map(r => r.aqi))

    // Pollutant concentrations (ug/m3) at which the gauge reads full, roughly AQI 150 for each.
    readonly property var pollutants: [
        { label: "PM2.5", value: root.current ? root.current.pm25 : null, full: 55 },
        { label: "PM10", value: root.current ? root.current.pm10 : null, full: 255 },
        { label: "OZONE", value: root.current ? root.current.ozone : null, full: 235 }
    ]

    readonly property string title: {
        const r = root.cursor_row;
        return r ? WeatherState.format_hour(new Date(r.dt)).toUpperCase() + "  AQI " + r.aqi + "  " + WeatherState.aqi_band(r.aqi).label.toUpperCase() : "";
    }

    function band_color(aqi) {
        return WeatherState.aqi_color(aqi);
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const rows = root.slice;
        if (rows.length === 0) return;

        const top_pad = 14;
        const label_h = 16;
        const plot_h = h - top_pad - label_h;
        const col_w = w / rows.length;
        const block_w = Math.max(4, Math.floor(col_w) - 3);
        const block_h = Math.max(2, (plot_h - root.block_gap * (root.card_blocks - 1)) / root.card_blocks);
        const small = Style.fs(-5) + "px \"" + Style.font_family + "\"";

        ctx.font = small;
        ctx.textAlign = "center";
        const label_w = ctx.measureText(WeatherState.format_hour(new Date(2000, 0, 1, 12)).toUpperCase()).width + 6;
        const step = [1, 2, 3, 4, 6, 8, 12].find(n => n * col_w >= label_w) || 12;

        for (let i = 0; i < rows.length; i++) {
            const selected = i === root.cursor_index;
            const color = root.band_color(rows[i].aqi);
            const used = Math.max(1, Math.min(root.card_blocks, Math.round(rows[i].aqi / root.full_scale * root.card_blocks)));
            const cx = i * col_w + col_w / 2;
            const x = Math.round(cx - block_w / 2);

            if (selected) {
                ctx.globalAlpha = 0.55;
                ctx.fillStyle = Style.selection_bg;
                ctx.fillRect(Math.round(i * col_w) + 1, 0, Math.round(col_w) - 2, h);
                ctx.globalAlpha = 1;
                ctx.strokeStyle = Theme.theme_primary_light;
                ctx.lineWidth = 2;
                ctx.strokeRect(Math.round(i * col_w) + 2, 1, Math.round(col_w) - 4, h - 2);
            }

            for (let b = 0; b < root.card_blocks; b++) {
                const y = Math.round(top_pad + plot_h - (b + 1) * block_h - b * root.block_gap);
                const bh = Math.round(block_h);
                if (b >= used) {
                    ctx.globalAlpha = 0.45;
                    ctx.fillStyle = Theme.bg_shadow;
                    ctx.fillRect(x, y, block_w, bh);
                    ctx.globalAlpha = 0.6;
                    ctx.strokeStyle = Style.frame_border_color;
                    ctx.lineWidth = 1;
                    ctx.strokeRect(x + 0.5, y + 0.5, block_w - 1, bh - 1);
                    continue;
                }
                const marked = selected && b === used - 1;
                ctx.globalAlpha = selected ? 0.95 : 0.6;
                ctx.fillStyle = color;
                ctx.fillRect(x, y, block_w, bh);
                ctx.globalAlpha = 1;
                ctx.strokeStyle = marked ? Style.text_strong : Qt.lighter(color, 1.3);
                ctx.lineWidth = marked ? 2 : 1;
                ctx.strokeRect(x + (marked ? 1 : 0.5), y + (marked ? 1 : 0.5), block_w - (marked ? 2 : 1), bh - (marked ? 2 : 1));
            }

            ctx.globalAlpha = 1;
            if (selected) {
                ctx.fillStyle = Style.text_strong;
                ctx.fillText(String(rows[i].aqi), cx, Math.max(10, top_pad + plot_h - used * (block_h + root.block_gap) - 2));
            }
            const near_selected = Math.abs(i - root.cursor_index) * col_w < label_w;
            if (selected || (i % step === 0 && !near_selected)) {
                ctx.fillStyle = selected ? Style.text_strong : Style.text_muted;
                ctx.fillText(WeatherState.format_hour(new Date(rows[i].dt)).toUpperCase(), Math.max(label_w / 2, Math.min(w - label_w / 2, cx)), h - 4);
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.ready
        radius: 6
        color: Qt.alpha(Theme.bg_shadow, 0.35)
        border.width: 2
        border.color: Style.frame_border_color

        Text {
            anchors.centerIn: parent
            text: WeatherState.aq_loading ? "LOADING..." : "AIR QUALITY UNAVAILABLE"
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.font_size
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        visible: root.ready

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

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    radius: 3
                    color: Style.selection_bg
                    border.width: 2
                    border.color: Theme.theme_primary_light

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 5
                        text: "NOW"
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                    }

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 5
                        text: root.current && root.current.aqi >= 0 ? root.current.aqi : "--"
                        color: root.current ? root.band_color(root.current.aqi) : Style.text_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(4)
                        font.bold: true
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.title
                        color: root.cursor_row ? root.band_color(root.cursor_row.aqi) : Style.text_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-1)
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.current ? "CURRENT  " + WeatherState.aqi_band(root.current.aqi).label.toUpperCase() : ""
                        color: Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-4)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 3
                        spacing: 6

                        Text {
                            text: "AQI"
                            color: Theme.theme_primary_light
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-5)
                        }

                        BlockGauge {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            value: root.cursor_row ? Math.min(1, root.cursor_row.aqi / root.full_scale) : 0
                            fill_color: root.cursor_row ? root.band_color(root.cursor_row.aqi) : Theme.theme_primary_light
                            mark_last: true
                        }
                    }
                }
            }
        }

        MemCardPanel {
            Layout.fillWidth: true
            Layout.preferredHeight: pollutant_col.implicitHeight + 3 + chrome_h
            heading: "POLLUTANTS"
            trailing: "UG/M3"
            trailing_color: Style.text_muted

            ColumnLayout {
                id: pollutant_col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 3
                spacing: 3

                Repeater {
                    model: root.pollutants

                    RowLayout {
                        id: pollutant
                        required property var modelData
                        readonly property real frac: pollutant.modelData.value !== null ? Math.min(1, pollutant.modelData.value / pollutant.modelData.full) : 0
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.preferredWidth: Style.px(46)
                            text: pollutant.modelData.label
                            color: Theme.theme_primary_light
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                        }

                        BlockGauge {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            value: pollutant.frac
                            fill_color: root.band_color(pollutant.frac * 150)
                        }

                        Text {
                            Layout.preferredWidth: Style.px(40)
                            horizontalAlignment: Text.AlignRight
                            text: pollutant.modelData.value !== null ? pollutant.modelData.value.toFixed(1) : "--"
                            color: Style.text_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-4)
                        }
                    }
                }
            }
        }

        MemCardPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            heading: "AQI  24H"
            trailing: root.cursor_row ? WeatherState.format_hour(new Date(root.cursor_row.dt)).toUpperCase() : ""

            Canvas {
                id: canvas
                anchors.fill: parent

                onPaint: root.paint(getContext("2d"), width, height)
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: WeatherState
                    function onAq_hoursChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: Style
                    function onFont_familyChanged() { canvas.requestPaint(); }
                    function onFont_sizeChanged() { canvas.requestPaint(); }
                    function onPalChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: Theme
                    function onTheme_primary_lightChanged() { canvas.requestPaint(); }
                }
                Connections {
                    target: TimeFormat
                    function onH24Changed() { canvas.requestPaint(); }
                }
                Connections {
                    target: root
                    function onCursor_indexChanged() { canvas.requestPaint(); }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mouse => {
                        if (root.slice.length === 0) return;
                        const idx = Math.floor(mouse.x / (width / root.slice.length));
                        root.on_select(Math.max(0, Math.min(root.slice.length - 1, idx)));
                    }
                }
            }
        }
    }
}
