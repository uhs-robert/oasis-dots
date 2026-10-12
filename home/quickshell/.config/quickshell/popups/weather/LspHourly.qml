// home/quickshell/.config/quickshell/popups/weather/LspHourly.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// The hours as a Neovim buffer scrolled sideways like `nowrap`: the value axis as the line-number gutter, diagnostic signs
// (E W I H) along the top of each hour for notable values, the plot in the buffer and the cursor hour as cursorcolumn and cursorline.
// The cursor hour's details trail as dim virtual text. sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity.
// h/l move the hour cursor (auto-scrolling into view); H/L jump +-1 day, same hour.
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property int text_px: Style.fs(-3)
    readonly property real line_h: Math.max(1, Math.ceil(metrics.height))
    readonly property real sign_h: root.line_h + 4
    readonly property real plot_top: root.sign_h + root.line_h + 6
    // The Precip sub keeps a row under the plot for the hourly amounts.
    readonly property real plot_bottom: track.chart_h - (root.sub === 1 ? root.line_h + 4 : 6)
    readonly property real gutter_w: Math.ceil(metrics.advanceWidth("-100°") + 14)
    readonly property real precip_full: WeatherState.metric ? 5 : 0.2
    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]
    readonly property var arrows: ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]
    // Gust thresholds are written in km/h.
    readonly property real kmh: WeatherState.metric ? 1 : 1.609

    readonly property var sign_letters: ["E", "W", "I", "H"]
    readonly property var sign_colors: [Style.pal.error, Style.pal.warning, Style.pal.info, Theme.hint]

    function arrow_of(deg) {
        return root.arrows[Math.round(((deg % 360) + 360) % 360 / 45) % 8];
    }

    function secondary_of(row) {
        return root.sub === 0 ? row.feels : root.sub === 2 ? row.wind_gusts : null;
    }

    function line_color(row) {
        switch (root.sub) {
        case 0: return WeatherState.temp_color(row.temp);
        case 1: return Style.pal.blue;
        case 2: return Style.pal.cyan;
        case 3: return WeatherState.uv_color(row.uv_index);
        default: return Style.pal.bright_cyan;
        }
    }

    // LSP-style findings for one hour, worst first: severity 0 error, 1 warning, 2 info, 3 hint.
    function diagnostics_of(row) {
        const list = [];
        const unit = WeatherState.metric ? " mm" : " in";
        const gust = row.wind_gusts * root.kmh;
        if (WeatherState.weather_color_keys[Math.round(row.code)] === "thunderstorm") list.push({ severity: 0, message: "thunderstorm" });
        if (row.precip >= (WeatherState.metric ? 4 : 0.16)) list.push({ severity: 0, message: "heavy rain " + row.precip.toFixed(WeatherState.metric ? 1 : 2) + unit });
        else if (row.pop >= 60 && row.precip > 0) list.push({ severity: 1, message: "rain likely " + row.pop + "%" });
        else if (row.pop >= 30) list.push({ severity: 2, message: "chance of rain " + row.pop + "%" });
        if (row.uv_index >= 11) list.push({ severity: 0, message: "extreme UV " + row.uv_index.toFixed(1) });
        else if (row.uv_index >= 8) list.push({ severity: 1, message: "very high UV " + row.uv_index.toFixed(1) });
        else if (row.uv_index >= 6) list.push({ severity: 2, message: "high UV " + row.uv_index.toFixed(1) });
        if (gust >= 75) list.push({ severity: 0, message: "storm gusts " + Math.round(row.wind_gusts) + " " + WeatherState.wind_unit() });
        else if (gust >= 50) list.push({ severity: 1, message: "strong gusts " + Math.round(row.wind_gusts) + " " + WeatherState.wind_unit() });
        else if (gust >= 35) list.push({ severity: 2, message: "gusty " + Math.round(row.wind_gusts) + " " + WeatherState.wind_unit() });
        else if (gust >= 25) list.push({ severity: 3, message: "breezy " + Math.round(row.wind_gusts) + " " + WeatherState.wind_unit() });
        if (root.sub === 4 && row.humidity >= 90) list.push({ severity: 3, message: "humidity " + row.humidity + "%" });
        return list.sort((a, b) => a.severity - b.severity);
    }

    // The padded data range snapped outward to a round step, in an even number of steps so the middle tick is round too.
    readonly property var axis: {
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return { min: 0, max: 1 };
        if (root.sub === 1 || root.sub === 4) return { min: 0, max: 100 };
        // Feels-like and gusts share the scale, so they count toward it or they would draw off the plot.
        const values = hrs.map(track.value_of).concat(hrs.map(root.secondary_of).filter(v => v !== null && v !== undefined));
        let lo = Math.min(...values), hi = Math.max(...values);
        const pad = Math.max(1, (hi - lo) * 0.1);
        lo -= pad;
        hi += pad;
        if (root.sub === 2) lo = Math.max(0, lo);
        if (root.sub === 3) {
            lo = 0;
            hi = Math.max(12, hi);
        }
        const steps = [1, 2, 4, 5, 10, 20, 50, 100];
        const step = steps.find(s => Math.ceil(hi / s) - Math.floor(lo / s) <= 8) || 100;
        const first = Math.floor(lo / step) * step;
        let n = Math.ceil(hi / step) - Math.floor(lo / step);
        if (n % 2 === 1) n++;
        return { min: first, max: first + n * step };
    }

    function y_of(v) {
        return root.plot_bottom - (v - root.axis.min) / (root.axis.max - root.axis.min || 1) * (root.plot_bottom - root.plot_top);
    }

    function tick_text(v) {
        return (Math.abs(v - Math.round(v)) < 0.05 ? String(Math.round(v)) : v.toFixed(1)) + (root.sub === 0 ? "°" : root.sub === 1 || root.sub === 4 ? "%" : "");
    }

    readonly property string axis_unit: root.sub === 0 ? "°" + WeatherState.unit_symbol() : root.sub === 2 ? WeatherState.wind_unit() : root.sub === 3 ? "UV" : "%"

    function label_of(row) {
        const v = track.value_of(row);
        return root.sub === 3 ? v.toFixed(1) : Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
    }

    function scroll_to_cursor() {
        track.scroll_to_cursor();
    }

    function request_scroll() {
        track.request_scroll();
    }

    onHour_cursorChanged: track.request_paint()
    onAxisChanged: track.request_paint()
    onPlot_bottomChanged: track.request_paint()
    onPlot_topChanged: track.request_paint()

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0 || root.plot_bottom <= root.plot_top + 10) return;
        const x_of = track.x_of;
        const total_w = hrs.length * track.hour_col_w;
        const mono = "\"" + Style.mono_font + "\"";
        ctx.font = root.text_px + "px " + mono;
        ctx.textBaseline = "middle";

        // Tick rules and day boundaries are indent guides: dotted and dim.
        ctx.strokeStyle = Style.text_muted;
        ctx.lineWidth = 1;
        ctx.setLineDash([1, 4]);
        ctx.globalAlpha = 0.45;
        for (const v of [root.axis.min, (root.axis.min + root.axis.max) / 2, root.axis.max]) {
            const y = Math.round(root.y_of(v)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(total_w, y);
            ctx.stroke();
        }
        ctx.globalAlpha = 0.6;
        for (const b of track.day_boundaries) {
            if (b.index === 0) continue;
            const x = Math.round(track.left_of(b.index)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(x, root.sign_h);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        ctx.setLineDash([]);
        ctx.globalAlpha = 1;

        ctx.fillStyle = Style.text_dim;
        ctx.textAlign = "left";
        ctx.font = "italic " + root.text_px + "px " + mono;
        for (const b of track.day_boundaries) ctx.fillText("-- " + b.label, track.left_of(b.index) + 4, root.sign_h + root.line_h / 2 + 2);
        ctx.font = root.text_px + "px " + mono;

        // The cursorline: the cursor hour's value carried across the whole buffer.
        const cursor = hrs[root.hour_cursor];
        if (cursor) {
            const y = Math.round(root.y_of(track.value_of(cursor))) + 0.5;
            ctx.strokeStyle = Style.caret_color;
            ctx.globalAlpha = 0.35;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(total_w, y);
            ctx.stroke();
            ctx.globalAlpha = 1;
        }

        if (root.sub === 1) {
            const base = root.plot_bottom;
            ctx.beginPath();
            ctx.moveTo(x_of(0), base);
            for (let i = 0; i < hrs.length; i++) ctx.lineTo(x_of(i), root.y_of(hrs[i].pop));
            ctx.lineTo(x_of(hrs.length - 1), base);
            ctx.closePath();
            ctx.fillStyle = Style.pal.blue;
            ctx.globalAlpha = 0.16;
            ctx.fill();
            ctx.globalAlpha = 1;
        }

        // Feels-like and gusts: a dashed series under the main line.
        const secondary = hrs.map(root.secondary_of);
        if (secondary[0] !== null && secondary[0] !== undefined) {
            ctx.setLineDash([4, 3]);
            ctx.strokeStyle = Style.text_muted;
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                const y = root.y_of(secondary[i]);
                if (i === 0) ctx.moveTo(x_of(i), y); else ctx.lineTo(x_of(i), y);
            }
            ctx.stroke();
            ctx.setLineDash([]);
        }

        ctx.lineWidth = 2;
        ctx.lineJoin = "round";
        for (let i = 1; i < hrs.length; i++) {
            ctx.strokeStyle = root.line_color(hrs[i]);
            ctx.beginPath();
            ctx.moveTo(x_of(i - 1), root.y_of(track.value_of(hrs[i - 1])));
            ctx.lineTo(x_of(i), root.y_of(track.value_of(hrs[i])));
            ctx.stroke();
        }

        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) {
            const selected = i === root.hour_cursor;
            const x = x_of(i), y = root.y_of(track.value_of(hrs[i]));
            const half = selected ? 3.5 : 2.5;
            ctx.fillStyle = root.line_color(hrs[i]);
            ctx.fillRect(x - half, y - half, half * 2, half * 2);
            ctx.fillStyle = selected ? Style.text_strong : Style.text_fg;
            ctx.globalAlpha = selected ? 1 : 0.8;
            ctx.fillText(root.label_of(hrs[i]), x, Math.max(root.plot_top - 6, y - 11));
            ctx.globalAlpha = 1;
        }

        if (root.sub === 1) {
            for (let i = 0; i < hrs.length; i++) {
                const amount = hrs[i].precip;
                if (amount < (WeatherState.metric ? 0.05 : 0.005)) continue;
                ctx.fillStyle = Style.pal.blue;
                ctx.fillText(amount.toFixed(WeatherState.metric ? 1 : 2), x_of(i), h - root.line_h / 2 - 1);
                const bar_h = Math.max(2, Math.min(1, amount / root.precip_full) * 18);
                ctx.globalAlpha = 0.5;
                ctx.fillRect(x_of(i) - 8, root.plot_bottom - bar_h, 16, bar_h);
                ctx.globalAlpha = 1;
            }
        }

        // Sign column: one badge per hour with a finding, drawn last so the plot never covers it.
        ctx.font = "bold " + root.text_px + "px " + mono;
        for (let i = 0; i < hrs.length; i++) {
            const found = root.diagnostics_of(hrs[i]);
            if (found.length === 0) continue;
            const sev = found[0].severity;
            const x = x_of(i);
            ctx.fillStyle = root.sign_colors[sev];
            ctx.globalAlpha = i === root.hour_cursor ? 0.32 : 0.16;
            ctx.fillRect(x - 8, 1, 16, root.sign_h - 2);
            ctx.globalAlpha = 1;
            ctx.fillText(root.sign_letters[sev], x, root.sign_h / 2 + 1);
        }
    }

    function span(text, color, italic) {
        const safe = String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;");
        return "<font color=\"" + color + "\">" + (italic ? "<i>" + safe + "</i>" : safe) + "</font>";
    }

    readonly property string virtual_text: {
        const r = root.cursor_row;
        if (!r) return "";
        const unit = WeatherState.unit_symbol();
        const dim = String(Style.text_dim);
        const parts = [];
        if (root.sub === 2) parts.push(root.arrow_of(r.wind_dir) + " " + WeatherState.wind_dir_label(r.wind_dir) + " " + Math.round(r.wind_speed) + "/" + Math.round(r.wind_gusts) + " " + WeatherState.wind_unit());
        if (root.sub === 3) parts.push("UV " + r.uv_index.toFixed(1) + " " + WeatherState.uv_band(r.uv_index).label);
        if (root.sub === 4) parts.push("humidity " + r.humidity + "%");
        parts.push(Math.round(r.temp) + "°" + unit + " feels " + Math.round(r.feels) + "°", r.pop + "% pop", r.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in"));
        parts.push(r.cond);
        return root.span(WeatherState.format_hour(new Date(r.dt)), String(Style.text_strong)) + root.span("   " + parts.join("  ·  "), dim, true);
    }

    readonly property string diagnostic_text: {
        const r = root.cursor_row;
        if (!r) return "";
        const found = root.diagnostics_of(r);
        if (found.length === 0) return root.span("✓ no diagnostics", String(Theme.ok), true);
        return found.map(d => root.span(root.sign_letters[d.severity], String(root.sign_colors[d.severity])) + root.span(" " + d.message, String(Style.text_dim), true)).join(root.span("   ", ""));
    }

    FontMetrics {
        id: metrics
        font.family: Style.mono_font
        font.pixelSize: root.text_px
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.line_h * 2 + 8

            Column {
                anchors.fill: parent
                anchors.topMargin: 2
                spacing: 2

                Row {
                    width: parent.width
                    height: root.line_h

                    Text {
                        width: root.gutter_w
                        horizontalAlignment: Text.AlignRight
                        rightPadding: 6
                        text: String(root.hour_cursor + 1)
                        color: Style.caret_color
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                        font.bold: true
                    }

                    Text {
                        width: parent.width - root.gutter_w
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: root.virtual_text
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
            // The shared view has always kept a 4px gap under the hour labels.
            Layout.bottomMargin: 4
            spacing: 0

            // The line-number gutter: the value axis, with the cursor hour's value lit like the current line number.
            Item {
                Layout.preferredWidth: root.gutter_w
                Layout.fillHeight: true

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    y: (root.sign_h - height) / 2
                    text: root.axis_unit
                    color: Style.text_dim
                    font.family: Style.mono_font
                    font.pixelSize: root.text_px
                    font.italic: true
                }

                Repeater {
                    model: [root.axis.min, (root.axis.min + root.axis.max) / 2, root.axis.max]

                    Text {
                        required property real modelData
                        readonly property bool hidden: !!root.cursor_row && Math.abs(root.y_of(track.value_of(root.cursor_row)) - root.y_of(modelData)) < root.line_h
                        visible: !hidden
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        y: root.y_of(modelData) - height / 2
                        text: root.tick_text(modelData)
                        color: Style.text_muted
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                    }
                }

                Text {
                    visible: !!root.cursor_row
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    y: root.cursor_row ? root.y_of(track.value_of(root.cursor_row)) - height / 2 : 0
                    text: root.cursor_row ? root.label_of(root.cursor_row) : ""
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

            HourlyTrack {
                id: track
                Layout.fillWidth: true
                Layout.fillHeight: true
                icon_row_h: 28
                hour_cursor: root.hour_cursor
                sub: root.sub
                on_select: i => root.on_select(i)
                scroll_x: root.scroll_x
                on_scroll: x => root.on_scroll(x)
                paint: root.paint
                highlight: Component {
                    Rectangle {
                        color: "transparent"

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 2
                            color: Style.caret_color
                        }
                    }
                }
                arrow_color: Style.pal.cyan
                label_color: Style.text_muted
                label_color_selected: Style.text_strong
                label_font_family: Style.mono_font
                label_px: root.text_px
                label_bold_selected: true

                underlay: Rectangle {
                    visible: root.hour_cursor >= 0 && root.hour_cursor < WeatherState.hours.length
                    x: track.left_of(root.hour_cursor)
                    width: track.hour_col_w
                    height: parent.height
                    color: Style.selection_bg
                }
            }
        }
    }
}
