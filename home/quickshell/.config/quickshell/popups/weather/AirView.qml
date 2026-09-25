// home/quickshell/.config/quickshell/popups/weather/AirView.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// Hourly's Air sub-view: big US AQI number, pollutant readouts, and a 24h trend. h/l move the hour cursor.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]

    Text {
        anchors.centerIn: parent
        visible: !WeatherState.aq_has_data
        text: WeatherState.aq_loading ? "Loading…" : "Air quality unavailable"
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: Style.font_size
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        visible: WeatherState.aq_has_data && !!WeatherState.aq_current

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Text {
                text: WeatherState.aq_current ? WeatherState.aq_current.aqi : "--"
                color: WeatherState.aq_current ? WeatherState.aqi_color(WeatherState.aq_current.aqi) : Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(20)
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: WeatherState.aq_current ? WeatherState.aqi_band(WeatherState.aq_current.aqi).label : ""
                color: WeatherState.aq_current ? WeatherState.aqi_color(WeatherState.aq_current.aqi) : Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.font_size
            }
        }

        GridLayout {
            id: readings
            Layout.fillWidth: true
            columns: Math.max(1, Math.min(3, Math.floor(readings.width / (Style.font_size * 6))))
            columnSpacing: 8
            rowSpacing: 4

            Repeater {
                model: [
                    { label: "PM2.5", value: WeatherState.aq_current ? WeatherState.aq_current.pm25 : null },
                    { label: "PM10", value: WeatherState.aq_current ? WeatherState.aq_current.pm10 : null },
                    { label: "Ozone", value: WeatherState.aq_current ? WeatherState.aq_current.ozone : null }
                ]

                ColumnLayout {
                    id: reading
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: reading.modelData.label; color: Style.text_muted; font.family: Style.font_family; font.pixelSize: Style.fs(-3) }
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: reading.modelData.value !== null ? reading.modelData.value.toFixed(1) : "--"; color: Theme.fg_core; font.family: Style.font_family; font.pixelSize: Style.fs(1) }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            readonly property var r: root.cursor_row
            text: r ? WeatherState.format_hour(new Date(r.dt)) + "  AQI " + r.aqi + " (" + WeatherState.aqi_band(r.aqi).label + ")" : ""
            color: Theme.fg_core
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
        }

        Canvas {
            id: canvas
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property var rows: root.slice

            onWidthChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const w = width, h = height;
                const rows = canvas.rows;
                if (rows.length === 0) return;

                const top_pad = 10;
                const bottom_pad = 20;
                const chart_h = h - top_pad - bottom_pad;
                const max_v = Math.max(100, ...rows.map(r => r.aqi));
                const col_w = w / rows.length;

                ctx.font = (Style.fs(-3)) + "px \"" + Style.font_family + "\"";
                ctx.textAlign = "center";
                const label_w = ctx.measureText(WeatherState.format_hour(new Date(2000, 0, 1, 12))).width + 8;
                const step = [3, 4, 6, 8, 12].find(n => n * col_w >= label_w) || 12;

                for (let i = 0; i < rows.length; i++) {
                    const row = rows[i];
                    const bar_h = Math.min(1, row.aqi / max_v) * chart_h;
                    const bar_w = Math.max(4, col_w * 0.6);
                    const x = i * col_w + (col_w - bar_w) / 2;
                    const y = top_pad + chart_h - bar_h;

                    if (i === root.cursor_index) {
                        ctx.fillStyle = Theme.bg_surface;
                        ctx.fillRect(i * col_w, top_pad, col_w, chart_h);
                    }

                    ctx.fillStyle = WeatherState.aqi_color(row.aqi);
                    ctx.fillRect(x, y, bar_w, bar_h);

                    if (i % step === 0) {
                        ctx.fillStyle = Style.text_muted;
                        ctx.fillText(WeatherState.format_hour(new Date(row.dt)), i * col_w + col_w / 2, h - 4);
                    }
                }
            }

            Connections {
                target: WeatherState
                function onAq_hoursChanged() { canvas.requestPaint(); }
            }
            Connections {
                target: Style
                function onFont_familyChanged() { canvas.requestPaint(); }
            }
            Connections {
                target: root
                function onCursor_indexChanged() { canvas.requestPaint(); }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    const rows = canvas.rows;
                    if (rows.length === 0) return;
                    const idx = Math.max(0, Math.min(rows.length - 1, Math.floor(mouse.x / (width / rows.length))));
                    root.on_select(idx);
                }
            }
        }
    }
}
