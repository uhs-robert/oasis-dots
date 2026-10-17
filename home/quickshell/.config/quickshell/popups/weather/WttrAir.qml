import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.features.clock
import "WttrArt.js" as WttrArt

// Hourly's Air sub-view as a btop panel: the US AQI and each pollutant as a gradient meter, then the 24h AQI trend
// as a braille graph with the cursor hour in reverse video. h/l move the hour cursor.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]
    readonly property bool ready: WeatherState.aq_has_data && !!WeatherState.aq_current

    readonly property int text_px: Style.fs(-3)
    // Reading metrics.font makes the advances rebind once the family and size land.
    readonly property real glyph_w: metrics.font.pixelSize > 0 ? Math.max(1, metrics.advanceWidth("⣿")) : 1
    // The panel is laid out on this text cell grid; block glyphs are not guaranteed to be one cell wide, so its meters are drawn as rectangles.
    readonly property real cell_w: metrics.font.pixelSize > 0 ? Math.max(1, metrics.advanceWidth("M")) : 1
    readonly property int lh: Math.max(1, Math.floor(metrics.height))
    readonly property int panel_cols: Math.max(24, Math.floor(root.width / root.cell_w))
    readonly property int panel_rows: 2 + 1 + root.meters.length
    readonly property color rule: Style.text_muted
    readonly property color inverse: Style.tab_active_fg
    readonly property var bars: ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    // The concentration (ug/m3) at which each meter reads full, near where its pollutant alone would put the AQI in the red.
    readonly property var meters: [
        { label: "PM2.5", key: "pm25", full: 150 },
        { label: "PM10", key: "pm10", full: 350 },
        { label: "Ozone", key: "ozone", full: 200 }
    ]
    readonly property int label_cols: 6
    readonly property int value_cols: 11

    // The btop meter ramp, green through yellow to red along the bar.
    function ramp(t) {
        return t < 0.5 ? Qt.tint(Theme.green, Qt.alpha(Theme.yellow, t * 2)) : Qt.tint(Theme.yellow, Qt.alpha(Theme.red, (t - 0.5) * 2));
    }

    readonly property string readout: {
        const r = root.cursor_row;
        if (!r) return "";
        const color = String(WeatherState.aqi_color(r.aqi));
        return WttrArt.runs([[WeatherState.format_hour(new Date(r.dt)) + "  ", String(Style.text_strong)], ["aqi ", String(Style.text_muted)], [String(r.aqi) + " ", color], [WeatherState.aqi_band(r.aqi).label, color]]);
    }

    FontMetrics {
        id: metrics
        font.family: Style.font_family
        font.pixelSize: root.text_px
    }

    Text {
        anchors.centerIn: parent
        visible: !root.ready
        text: WeatherState.aq_loading ? "Loading…" : "Air quality unavailable"
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: Style.font_size
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4
        visible: root.ready

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: WttrArt.runs([["$ ", String(Theme.theme_secondary)], ["curl air-quality-api.open-meteo.com", String(Theme.fg_core)]])
            font.family: Style.font_family
            font.pixelSize: root.text_px
        }

        Canvas {
            id: panel
            Layout.fillWidth: true
            Layout.preferredHeight: root.panel_rows * root.lh

            function put(ctx, text, col, row, color, align) {
                ctx.textAlign = align || "left";
                ctx.fillStyle = color;
                ctx.fillText(text, col * root.cell_w, row * root.lh);
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cur = WeatherState.aq_current;
                if (!root.ready || !cur) return;
                const cw = root.cell_w, lh = root.lh, cols = root.panel_cols;
                ctx.font = root.text_px + "px \"" + Style.font_family + "\"";
                ctx.textBaseline = "top";

                const left = cw / 2, right = (cols - 0.5) * cw, top = lh / 2, bottom = (root.panel_rows - 0.5) * lh;
                const title = "air quality";
                const title_end = (3 + title.length) * cw;
                ctx.strokeStyle = root.rule;
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(2.5 * cw, Math.round(top) + 0.5);
                ctx.lineTo(left, Math.round(top) + 0.5);
                ctx.lineTo(left, Math.round(bottom) + 0.5);
                ctx.lineTo(right, Math.round(bottom) + 0.5);
                ctx.lineTo(right, Math.round(top) + 0.5);
                ctx.lineTo(title_end + cw, Math.round(top) + 0.5);
                ctx.stroke();
                panel.put(ctx, title, 3, 0, Style.text_strong);

                const aqi_color = WeatherState.aqi_color(cur.aqi);
                panel.put(ctx, "AQI", 2, 1, Style.text_muted);
                panel.put(ctx, String(cur.aqi), 6, 1, aqi_color);
                panel.put(ctx, WeatherState.aqi_band(cur.aqi).label, 6 + String(cur.aqi).length + 2, 1, aqi_color);

                const bar_col = 2 + root.label_cols + 1;
                const bar_cells = Math.max(4, cols - bar_col - root.value_cols - 3);
                for (let m = 0; m < root.meters.length; m++) {
                    const meter = root.meters[m], row = 2 + m;
                    const fill = Math.max(0, Math.min(1, cur[meter.key] / meter.full));
                    panel.put(ctx, meter.label, 2, row, Style.text_muted);
                    // Full-height cells with a hairline gap, like btop's meters; unlit cells stay as a dim track.
                    for (let c = 0; c < bar_cells; c++) {
                        const lit = Math.max(0, Math.min(1, fill * bar_cells - c));
                        const x = (bar_col + c) * cw;
                        ctx.fillStyle = Qt.alpha(Style.text_dim, 0.22);
                        ctx.fillRect(x + 1, row * lh + 2, cw - 2, lh - 4);
                        if (lit > 0) {
                            ctx.fillStyle = root.ramp(bar_cells > 1 ? c / (bar_cells - 1) : 0);
                            ctx.fillRect(x + 1, row * lh + 2, Math.max(1, (cw - 2) * lit), lh - 4);
                        }
                    }
                    panel.put(ctx, cur[meter.key].toFixed(1) + " µg/m³", cols - 2, row, root.ramp(fill), "right");
                }
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: root
                function onCell_wChanged() { panel.requestPaint(); }
                function onLhChanged() { panel.requestPaint(); }
                function onReadyChanged() { panel.requestPaint(); }
            }
            Connections {
                target: WeatherState
                function onAq_currentChanged() { panel.requestPaint(); }
            }
            Connections {
                target: Style
                function onFont_familyChanged() { panel.requestPaint(); }
                function onFont_sizeChanged() { panel.requestPaint(); }
                function onPalChanged() { panel.requestPaint(); }
                function onText_primaryChanged() { panel.requestPaint(); }
                function onText_mutedChanged() { panel.requestPaint(); }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(root.lh, implicitHeight)
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: root.readout
            color: Style.text_fg
            font.family: Style.font_family
            font.pixelSize: root.text_px
        }

        Canvas {
            id: canvas
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property int axis_chars: 5
            readonly property int total_rows: Math.floor(canvas.height / root.lh)
            // Graph rows, then the histogram row and the hour label row.
            readonly property int graph_rows: Math.max(2, canvas.total_rows - 2)
            readonly property real plot_x: canvas.axis_chars * root.glyph_w
            readonly property real col_w: root.slice.length > 0 ? (canvas.width - canvas.plot_x) / root.slice.length : 0
            readonly property real axis_max: Math.ceil(Math.max(100, ...root.slice.map(r => r.aqi)) / 50) * 50

            function axis_label(r) {
                const mid = Math.round((canvas.graph_rows - 1) / 2);
                const value = r === 0 ? canvas.axis_max : r === canvas.graph_rows - 1 ? 0 : r === mid && canvas.graph_rows >= 5 ? canvas.axis_max / 2 : -1;
                const label = value >= 0 ? String(value) : "";
                return label.padStart(canvas.axis_chars - 1, " ") + (label !== "" ? "┤" : "│");
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const rows = root.slice;
                if (rows.length === 0 || canvas.total_rows < 4) return;
                const gw = root.glyph_w, lh = root.lh;
                ctx.font = root.text_px + "px \"" + Style.font_family + "\"";
                ctx.textBaseline = "top";
                ctx.textAlign = "left";

                ctx.fillStyle = root.rule;
                for (let r = 0; r < canvas.graph_rows; r++) ctx.fillText(canvas.axis_label(r), 0, r * lh);

                const cph = Math.max(1, Math.floor(canvas.col_w / gw));
                const chars_x = (canvas.col_w - cph * gw) / 2;
                const hist_row = canvas.graph_rows, label_row = canvas.graph_rows + 1;
                const cursor = root.cursor_index;

                // Reverse video on the text rows only; the graph rows get a faint tint so the trace keeps its colour.
                const cursor_x = canvas.plot_x + cursor * canvas.col_w;
                ctx.fillStyle = Qt.alpha(Style.tab_active_bg, 0.14);
                ctx.fillRect(cursor_x, 0, canvas.col_w, hist_row * lh);
                ctx.fillStyle = Style.tab_active_bg;
                ctx.fillRect(cursor_x, hist_row * lh, canvas.col_w, 2 * lh);

                const masks = WttrArt.braille_masks(rows.map(r => r.aqi), canvas.graph_rows, cph, 0, canvas.axis_max, false);
                const glyph = bits => String.fromCharCode(0x2800 + bits);
                const wide = Math.max(1, cph - 1);
                for (let i = 0; i < rows.length; i++) {
                    const x0 = canvas.plot_x + i * canvas.col_w + chars_x;
                    ctx.fillStyle = WeatherState.aqi_color(rows[i].aqi);
                    for (let r = 0; r < canvas.graph_rows; r++) ctx.fillText(masks[i][r].map(glyph).join(""), x0, r * lh);
                    if (rows[i].aqi > 0) {
                        const level = Math.max(0, Math.min(7, Math.ceil(rows[i].aqi / canvas.axis_max * 8) - 1));
                        ctx.fillStyle = i === cursor ? root.inverse : WeatherState.aqi_color(rows[i].aqi);
                        ctx.fillText(root.bars[level].repeat(wide), x0 + (cph - wide) / 2 * gw, hist_row * lh);
                    }
                }

                // Hour labels thin out to fit their width; the cursor's always shows and pushes its neighbours aside.
                const labels = rows.map(r => WeatherState.format_hour(new Date(r.dt)));
                const label_w = ctx.measureText(labels[cursor]).width + gw;
                const step = [1, 2, 3, 4, 6, 8, 12].find(n => n * canvas.col_w >= label_w) || 12;
                for (let i = 0; i < rows.length; i++) {
                    const selected = i === cursor;
                    if (!selected && (i % step !== 0 || Math.abs(i - cursor) * canvas.col_w < label_w)) continue;
                    const text_w = ctx.measureText(labels[i]).width;
                    const x = Math.max(0, Math.min(canvas.width - text_w, canvas.plot_x + (i + 0.5) * canvas.col_w - text_w / 2));
                    if (selected) {
                        ctx.fillStyle = Style.tab_active_bg;
                        ctx.fillRect(x - gw / 2, label_row * lh, text_w + gw, lh);
                    }
                    ctx.fillStyle = selected ? root.inverse : Style.text_muted;
                    ctx.fillText(labels[i], x, label_row * lh);
                }
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: root
                function onCursor_indexChanged() { canvas.requestPaint(); }
                function onSliceChanged() { canvas.requestPaint(); }
                function onGlyph_wChanged() { canvas.requestPaint(); }
                function onLhChanged() { canvas.requestPaint(); }
            }
            Connections {
                target: Style
                function onFont_familyChanged() { canvas.requestPaint(); }
                function onFont_sizeChanged() { canvas.requestPaint(); }
                function onPalChanged() { canvas.requestPaint(); }
                function onText_primaryChanged() { canvas.requestPaint(); }
                function onText_mutedChanged() { canvas.requestPaint(); }
            }
            Connections {
                target: TimeFormat
                function onH24Changed() { canvas.requestPaint(); }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    const idx = Math.floor((mouse.x - canvas.plot_x) / canvas.col_w);
                    if (mouse.x >= canvas.plot_x && idx >= 0 && idx < root.slice.length) root.on_select(idx);
                }
            }
        }
    }
}
