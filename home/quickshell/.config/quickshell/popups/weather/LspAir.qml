// home/quickshell/.config/quickshell/popups/weather/LspAir.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// Hourly's Air sub-view as a Neovim buffer: `:checkhealth air` with the pollutants as inlay hints, then the 24 AQI hours
// plotted under a sign column (E unhealthy and worse, W sensitive groups, I moderate) with the AQI axis as the line-number gutter.
// h/l move the hour cursor, clamped to these 24 hours.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property int text_px: Style.fs(-3)
    readonly property real line_h: Math.max(1, Math.ceil(metrics.height))
    readonly property real sign_h: root.line_h + 4
    readonly property real label_h: root.line_h + 4
    readonly property real gutter_w: Math.ceil(metrics.advanceWidth("-300") + 14)
    readonly property real plot_top: root.sign_h + 6
    readonly property real plot_bottom: canvas.height - root.label_h

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]
    readonly property bool ready: WeatherState.aq_has_data && !!WeatherState.aq_current

    readonly property var sign_letters: ["E", "W", "I"]
    readonly property var sign_colors: [Style.pal.error, Style.pal.warning, Style.pal.info]
    readonly property var band_edges: [50, 100, 150]

    // Axis in whole bands of 50 so the dotted rules sit on the category edges.
    readonly property real axis_max: Math.max(150, Math.ceil(Math.max(0, ...root.slice.map(r => r.aqi)) / 50) * 50)

    // Sign severity 0 error, 1 warning, 2 info, -1 none.
    function severity_of(aqi) {
        return aqi >= 151 ? 0 : aqi >= 101 ? 1 : aqi >= 51 ? 2 : -1;
    }

    function health_status(aqi) {
        const sev = root.severity_of(aqi);
        return sev === 0 ? "ERROR" : sev === 1 ? "WARNING" : sev === 2 ? "ADVICE" : "OK";
    }

    function y_of(v) {
        return root.plot_bottom - Math.min(1, v / root.axis_max) * (root.plot_bottom - root.plot_top);
    }

    function span(text, color, bold, italic) {
        const safe = String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;");
        let body = bold ? "<b>" + safe + "</b>" : safe;
        if (italic) body = "<i>" + body + "</i>";
        return "<font color=\"" + color + "\">" + body + "</font>";
    }

    // One checkhealth line: "- OK key value", the status in its health colour.
    function health(status, key, value, value_color) {
        const colors = { OK: Theme.ok, WARNING: Theme.warning, ERROR: Theme.error, ADVICE: Theme.info };
        return root.span("- ", String(Style.text_muted)) + root.span(status, String(colors[status]), true) + root.span(" " + key + " ", String(Style.text_dim)) + root.span(value, String(value_color));
    }

    // A pollutant reading with its name as an inlay hint ahead of the value.
    function reading(name, value) {
        return root.span("  " + name + ":", String(Style.text_dim), false, true) + root.span(" " + (value !== null && value !== undefined ? value.toFixed(1) : "--"), String(Style.text_strong)) + root.span(" µg/m³", String(Style.text_dim));
    }

    readonly property string aqi_line: {
        const c = WeatherState.aq_current;
        if (!c) return "";
        const color = WeatherState.aqi_color(c.aqi);
        return root.health(root.health_status(c.aqi), "us aqi", c.aqi + " " + WeatherState.aqi_band(c.aqi).label, color);
    }

    readonly property string cursor_text: {
        const r = root.cursor_row;
        if (!r) return "";
        return root.span(WeatherState.format_hour(new Date(r.dt)), String(Style.text_strong)) + root.span("   AQI ", String(Style.text_dim), false, true) + root.span(r.aqi, String(WeatherState.aqi_color(r.aqi)), true) + root.span("  ·  " + WeatherState.aqi_band(r.aqi).label, String(Style.text_dim), false, true);
    }

    readonly property string diagnostic_text: {
        const r = root.cursor_row;
        if (!r) return "";
        const sev = root.severity_of(r.aqi);
        if (sev < 0) return root.span("✓ no diagnostics", String(Theme.ok), false, true);
        return root.span(root.sign_letters[sev], String(root.sign_colors[sev]), true) + root.span(" " + WeatherState.aqi_band(r.aqi).label.toLowerCase(), String(Style.text_dim), false, true);
    }

    onCursor_indexChanged: canvas.requestPaint()
    onAxis_maxChanged: canvas.requestPaint()
    onPlot_bottomChanged: canvas.requestPaint()

    FontMetrics {
        id: metrics
        font.family: Style.mono_font
        font.pixelSize: root.text_px
    }

    Text {
        anchors.centerIn: parent
        visible: !WeatherState.aq_has_data
        text: WeatherState.aq_loading ? "Loading…" : "Air quality unavailable"
        color: Style.text_dim
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-1)
        font.italic: true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        visible: root.ready

        Column {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            spacing: 2

            Text {
                text: ":checkhealth air"
                color: Style.text_dim
                font.family: Style.mono_font
                font.pixelSize: root.text_px
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                topPadding: 2
                textFormat: Text.StyledText
                text: root.span("air: ", String(Style.pal.primary), true) + root.span("health check", String(Style.text_strong), true)
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: root.text_px
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: root.aqi_line
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: root.text_px
            }

            Repeater {
                model: [
                    { name: "pm2.5", value: WeatherState.aq_current ? WeatherState.aq_current.pm25 : null },
                    { name: "pm10", value: WeatherState.aq_current ? WeatherState.aq_current.pm10 : null },
                    { name: "ozone", value: WeatherState.aq_current ? WeatherState.aq_current.ozone : null }
                ]

                Text {
                    required property var modelData
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: root.reading(modelData.name, modelData.value)
                    color: Style.text_fg
                    font.family: Style.mono_font
                    font.pixelSize: root.text_px
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.preferredHeight: root.line_h * 2 + 4

            Column {
                anchors.fill: parent
                spacing: 2

                Row {
                    width: parent.width
                    height: root.line_h

                    Text {
                        width: root.gutter_w
                        horizontalAlignment: Text.AlignRight
                        rightPadding: 6
                        text: String(root.cursor_index + 1)
                        color: Style.caret_color
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                        font.bold: true
                    }

                    Text {
                        width: parent.width - root.gutter_w
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: root.cursor_text
                        color: Style.text_fg
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                    }
                }

                Row {
                    width: parent.width
                    height: root.line_h

                    Item {
                        width: root.gutter_w
                        height: parent.height
                    }

                    Text {
                        width: parent.width - root.gutter_w
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: root.diagnostic_text
                        color: Style.text_fg
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: 4
            spacing: 0

            // The line-number gutter: the AQI axis, with the cursor hour's value lit like the current line number.
            Item {
                Layout.preferredWidth: root.gutter_w
                Layout.fillHeight: true

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    y: (root.sign_h - height) / 2
                    text: "aqi"
                    color: Style.text_dim
                    font.family: Style.mono_font
                    font.pixelSize: root.text_px
                    font.italic: true
                }

                Repeater {
                    model: [0, 50, 100, 150].concat(root.axis_max > 150 ? [root.axis_max] : [])

                    Text {
                        required property real modelData
                        readonly property bool hidden: !!root.cursor_row && Math.abs(root.y_of(root.cursor_row.aqi) - root.y_of(modelData)) < root.line_h
                        visible: !hidden
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        y: root.y_of(modelData) - height / 2
                        text: String(modelData)
                        color: Style.text_muted
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                    }
                }

                Text {
                    visible: !!root.cursor_row
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    y: root.cursor_row ? root.y_of(root.cursor_row.aqi) - height / 2 : 0
                    text: root.cursor_row ? String(root.cursor_row.aqi) : ""
                    color: Style.caret_color
                    font.family: Style.mono_font
                    font.pixelSize: root.text_px
                    font.bold: true
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: Style.pal.bg_surface
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    visible: !!root.cursor_row
                    x: root.cursor_index * canvas.col_w
                    width: canvas.col_w
                    height: parent.height
                    color: Style.selection_bg
                }

                Canvas {
                    id: canvas
                    anchors.fill: parent

                    readonly property real col_w: canvas.width / Math.max(1, root.slice.length)

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const rows = root.slice;
                        if (rows.length === 0 || root.plot_bottom <= root.plot_top + 10) return;
                        const w = width, h = height;
                        const col_w = canvas.col_w;
                        const x_of = i => (i + 0.5) * col_w;
                        const mono = "\"" + Style.mono_font + "\"";
                        ctx.font = root.text_px + "px " + mono;
                        ctx.textBaseline = "middle";

                        // Category edges as dotted rules, each in the colour of the band it opens.
                        ctx.setLineDash([1, 4]);
                        ctx.lineWidth = 1;
                        ctx.globalAlpha = 0.55;
                        for (const edge of root.band_edges) {
                            ctx.strokeStyle = WeatherState.aqi_color(edge);
                            const y = Math.round(root.y_of(edge)) + 0.5;
                            ctx.beginPath();
                            ctx.moveTo(0, y);
                            ctx.lineTo(w, y);
                            ctx.stroke();
                        }
                        ctx.setLineDash([]);
                        ctx.globalAlpha = 1;

                        const cursor = rows[root.cursor_index];
                        const cursor_y = Math.round(root.y_of(cursor.aqi)) + 0.5;
                        ctx.strokeStyle = Style.caret_color;
                        ctx.globalAlpha = 0.35;
                        ctx.beginPath();
                        ctx.moveTo(0, cursor_y);
                        ctx.lineTo(w, cursor_y);
                        ctx.stroke();
                        ctx.globalAlpha = 1;

                        ctx.lineWidth = 2;
                        ctx.lineJoin = "round";
                        for (let i = 1; i < rows.length; i++) {
                            ctx.strokeStyle = WeatherState.aqi_color(rows[i].aqi);
                            ctx.beginPath();
                            ctx.moveTo(x_of(i - 1), root.y_of(rows[i - 1].aqi));
                            ctx.lineTo(x_of(i), root.y_of(rows[i].aqi));
                            ctx.stroke();
                        }

                        for (let i = 0; i < rows.length; i++) {
                            const half = i === root.cursor_index ? 3.5 : 2.5;
                            ctx.fillStyle = WeatherState.aqi_color(rows[i].aqi);
                            ctx.fillRect(x_of(i) - half, root.y_of(rows[i].aqi) - half, half * 2, half * 2);
                        }

                        // Hour labels along the bottom, thinned to what fits.
                        ctx.textAlign = "center";
                        const label_w = ctx.measureText(WeatherState.format_hour(new Date(2000, 0, 1, 12))).width + 8;
                        const step = [1, 2, 3, 4, 6, 8, 12].find(n => n * col_w >= label_w) || 12;
                        for (let i = 0; i < rows.length; i++) {
                            const selected = i === root.cursor_index;
                            const crowds_cursor = !selected && Math.abs(i - root.cursor_index) * col_w < label_w;
                            if ((i % step !== 0 && !selected) || crowds_cursor) continue;
                            ctx.fillStyle = selected ? Style.text_strong : Style.text_muted;
                            ctx.fillText(WeatherState.format_hour(new Date(rows[i].dt)), Math.max(label_w / 2, Math.min(w - label_w / 2, x_of(i))), h - root.label_h / 2 + 2);
                        }
                        ctx.fillStyle = Style.caret_color;
                        ctx.fillRect(root.cursor_index * col_w, h - 2, col_w, 2);

                        // Sign column: one badge per hour with a finding.
                        ctx.font = "bold " + root.text_px + "px " + mono;
                        for (let i = 0; i < rows.length; i++) {
                            const sev = root.severity_of(rows[i].aqi);
                            if (sev < 0) continue;
                            ctx.fillStyle = root.sign_colors[sev];
                            ctx.globalAlpha = i === root.cursor_index ? 0.32 : 0.16;
                            ctx.fillRect(i * col_w + 1, 1, col_w - 2, root.sign_h - 2);
                            ctx.globalAlpha = 1;
                            ctx.fillText(root.sign_letters[sev], x_of(i), root.sign_h / 2 + 1);
                        }
                    }

                    Connections {
                        target: WeatherState
                        function onAq_hoursChanged() { canvas.requestPaint(); }
                    }
                    Connections {
                        target: Style
                        function onFont_familyChanged() { canvas.requestPaint(); }
                        function onFont_sizeChanged() { canvas.requestPaint(); }
                        function onPalChanged() { canvas.requestPaint(); }
                        function onText_mutedChanged() { canvas.requestPaint(); }
                        function onText_strongChanged() { canvas.requestPaint(); }
                        function onCaret_colorChanged() { canvas.requestPaint(); }
                    }
                    Connections {
                        target: TimeFormat
                        function onH24Changed() { canvas.requestPaint(); }
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
}
