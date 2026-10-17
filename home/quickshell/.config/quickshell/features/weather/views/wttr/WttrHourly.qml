import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.features.weather
import qs.features.weather.views.shared
import "../../../../styles/terminal/widgets/WttrArt.js" as WttrArt

// `curl wttr.in/?format=v2`: a braille-dot graph with a value axis, a precipitation histogram under it and the
// hour row as text, the cursor hour in reverse video. sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity.
// h/l move the hour cursor (auto-scrolling into view); H/L jump +-1 day, same hour.
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var sub_names: ["temp", "precip", "wind", "uv", "humidity"]
    readonly property int text_px: Style.fs(-3)
    // Reading metrics.font makes the advances rebind once the family and size land.
    readonly property real glyph_w: metrics.font.pixelSize > 0 ? Math.max(1, metrics.advanceWidth("⣿")) : 1
    readonly property int lh: Math.max(1, Math.floor(metrics.height))
    // Characters per hour column; each holds two dot columns.
    readonly property int chars: Math.max(3, Math.floor(track.hour_col_w / root.glyph_w))
    readonly property real chars_x: (track.hour_col_w - root.chars * root.glyph_w) / 2
    readonly property int axis_chars: 5
    readonly property int total_rows: Math.floor(track.chart_h / root.lh)
    // Day labels, the value row and the histogram row (plus the amount row on Precip) share the chart with the graph.
    readonly property int amount_rows: root.sub === 1 ? 1 : 0
    readonly property int graph_rows: Math.max(2, root.total_rows - 3 - root.amount_rows)
    readonly property int values_row: 1 + root.graph_rows
    readonly property int hist_row: root.values_row + 1

    readonly property real precip_full: WeatherState.metric ? 5 : 0.2
    readonly property var bars: ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    readonly property var arrows: ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]
    readonly property color rule: Style.text_muted
    readonly property color inverse: Style.tab_active_fg
    readonly property var art_colors: ({ y: Theme.yellow, c: Qt.tint(Theme.fg_core, Qt.alpha(Theme.fg_dim, 0.55)), d: Theme.fg_dim, r: Theme.blue, s: Theme.fg_strong, t: Theme.bright_yellow, f: Theme.fg_dim, u: Theme.fg_muted })

    function arrow_of(deg) {
        return root.arrows[Math.round(((deg % 360) + 360) % 360 / 45) % 8];
    }

    function secondary_of(row) {
        return root.sub === 0 ? row.feels : root.sub === 2 ? row.wind_gusts : null;
    }

    function line_color(row) {
        switch (root.sub) {
        case 0: return WeatherState.temp_color(row.temp);
        case 1: return Theme.blue;
        case 2: return Style.pal.cyan;
        case 3: return WeatherState.uv_color(row.uv_index);
        default: return Style.pal.bright_cyan;
        }
    }

    // The padded data range snapped outward to a round step, in an even number of steps so the middle tick is round too.
    readonly property var axis: {
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return { min: 0, max: 1 };
        if (root.sub === 1 || root.sub === 4) return { min: 0, max: 100 };
        // Feels-like and gusts share the scale, so they count toward it or they would draw off the graph.
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

    function tick_text(v) {
        const s = Math.abs(v - Math.round(v)) < 0.05 ? String(Math.round(v)) : v.toFixed(1);
        return s + (root.sub === 0 ? "°" : root.sub === 1 || root.sub === 4 ? "%" : "");
    }

    readonly property string axis_unit: root.sub === 0 ? "°" + WeatherState.unit_symbol() : root.sub === 2 ? WeatherState.wind_unit() : root.sub === 3 ? "UV" : "%"

    function axis_line(r) {
        const n = root.axis_chars - 1;
        let label = "";
        if (r === 0) label = root.axis_unit;
        else if (r === root.hist_row) label = WeatherState.metric ? "mm" : "in";
        else if (r === 1) label = root.tick_text(root.axis.max);
        else if (r === root.graph_rows) label = root.tick_text(root.axis.min);
        else if (r === Math.round((1 + root.graph_rows) / 2) && root.graph_rows >= 3) label = root.tick_text((root.axis.min + root.axis.max) / 2);
        const tick = r >= 1 && r <= root.graph_rows ? (label !== "" ? "┤" : "│") : " ";
        return label.slice(0, n).padStart(n, " ") + tick;
    }

    function scroll_to_cursor() {
        track.scroll_to_cursor();
    }

    function request_scroll() {
        track.request_scroll();
    }

    property real view_x: root.scroll_x

    onView_xChanged: track.request_paint()
    onHour_cursorChanged: track.request_paint()
    onGlyph_wChanged: track.request_paint()
    onLhChanged: track.request_paint()
    onGraph_rowsChanged: track.request_paint()
    onAxisChanged: track.request_paint()

    function plot_masks(hrs, value_of, dashed) {
        return WttrArt.braille_masks(hrs.map(value_of), root.graph_rows, root.chars, root.axis.min, root.axis.max, dashed);
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0 || root.total_rows < 5) return;
        const gw = root.glyph_w, lh = root.lh;
        ctx.font = root.text_px + "px \"" + Style.font_family + "\"";
        ctx.textBaseline = "top";
        ctx.textAlign = "left";

        const rule_rows = root.total_rows;
        ctx.fillStyle = root.rule;
        for (const b of track.day_boundaries) {
            if (b.index > 0) for (let r = 0; r < rule_rows; r++) ctx.fillText("│", track.left_of(b.index) - gw / 2, r * lh);
        }
        // The label of the day under the left edge follows the scroll, as a terminal would print it, and stops at the next day's rule.
        ctx.fillStyle = Style.text_fg;
        const bounds = track.day_boundaries;
        for (let k = 0; k < bounds.length; k++) {
            const next_left = k + 1 < bounds.length ? track.left_of(bounds[k + 1].index) : Infinity;
            const own_x = track.left_of(bounds[k].index) + gw;
            const x = Math.min(Math.max(own_x, root.view_x + gw), next_left - ctx.measureText(bounds[k].label).width - gw);
            if (x >= own_x) ctx.fillText(bounds[k].label, x, 0);
        }

        const primary = root.plot_masks(hrs, track.value_of, false);
        const secondary = root.sub === 0 || root.sub === 2 ? root.plot_masks(hrs, root.secondary_of, true) : null;
        const glyph = bits => String.fromCharCode(0x2800 + bits);

        for (let i = 0; i < hrs.length; i++) {
            const x0 = track.left_of(i) + root.chars_x;
            const selected = i === root.hour_cursor;
            const color = root.line_color(hrs[i]);
            const text_color = selected ? root.inverse : color;
            for (let r = 0; r < root.graph_rows; r++) {
                if (secondary) {
                    const own = primary[i][r];
                    const text = secondary[i][r].map((m, c) => glyph(m & ~own[c])).join("");
                    if (/[^⠀]/.test(text)) {
                        ctx.fillStyle = Style.text_muted;
                        ctx.fillText(text, x0, (1 + r) * lh);
                    }
                }
                ctx.fillStyle = color;
                ctx.fillText(primary[i][r].map(glyph).join(""), x0, (1 + r) * lh);
            }

            const v = track.value_of(hrs[i]);
            const label = root.sub === 3 ? v.toFixed(1) : Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : "");
            ctx.fillStyle = text_color;
            ctx.fillText(label, track.left_of(i) + (track.hour_col_w - ctx.measureText(label).width) / 2, root.values_row * lh);

            const amount = hrs[i].precip;
            if (amount > 0) {
                const level = Math.max(0, Math.min(7, Math.ceil(amount / root.precip_full * 8) - 1));
                const wide = Math.max(1, root.chars - 2);
                ctx.fillStyle = selected ? root.inverse : Theme.blue;
                ctx.fillText(root.bars[level].repeat(wide), x0 + (root.chars - wide) / 2 * gw, root.hist_row * lh);
                if (root.sub === 1 && amount >= (WeatherState.metric ? 0.05 : 0.005)) {
                    const text = amount.toFixed(WeatherState.metric ? 1 : 2);
                    ctx.fillText(text, track.left_of(i) + (track.hour_col_w - ctx.measureText(text).width) / 2, (root.hist_row + 1) * lh);
                }
            }
        }
    }

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]

    function pair(key, value, color) {
        return [[key + " ", Style.text_muted], [value, color || Style.text_fg], ["  ", ""]];
    }

    readonly property string readout: {
        const r = root.cursor_row;
        if (!r) return "";
        const unit = WeatherState.unit_symbol();
        let list = [[WeatherState.format_hour(new Date(r.dt)) + "  ", String(Style.text_strong)]];
        list = list.concat(root.pair("temp", Math.round(r.temp) + "°" + unit, WeatherState.temp_color(r.temp)));
        list = list.concat(root.pair("pop", r.pop + "%", Theme.blue), root.pair("precip", r.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in"), Theme.blue));
        if (root.sub === 2) list = list.concat(root.pair("wind", root.arrow_of(r.wind_dir) + " " + Math.round(r.wind_speed) + "/" + Math.round(r.wind_gusts) + " " + WeatherState.wind_unit(), Style.pal.cyan));
        if (root.sub === 3) list = list.concat(root.pair("uv", r.uv_index.toFixed(1) + " " + WeatherState.uv_band(r.uv_index).label, WeatherState.uv_color(r.uv_index)));
        if (root.sub === 4) list = list.concat(root.pair("hum", r.humidity + "%", Style.pal.bright_cyan));
        list.push([r.cond, String(Style.text_fg)]);
        return WttrArt.runs(list.map(e => [e[0], String(e[1])]));
    }

    // The cell's two icon lines: the condition's mini drawing, or on Wind the direction arrow over the speed.
    function icon_text(d, selected) {
        const tone = (color) => selected ? "" : String(color);
        if (root.sub === 2) return WttrArt.runs([[root.arrow_of(d.wind_dir), tone(Style.pal.cyan)]]) + "<br>" + WttrArt.runs([[String(Math.round(d.wind_speed)), tone(Style.text_fg)]]);
        const art = WttrArt.minis[WttrArt.kind(d.code)];
        const lines = [0, 1].map(l => selected ? WttrArt.runs([[art.lines[l], ""]]) : WttrArt.runs(WttrArt.line_runs(art, l, root.art_colors)));
        return lines.join("<br>");
    }

    FontMetrics {
        id: metrics
        font.family: Style.font_family
        font.pixelSize: root.text_px
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: WttrArt.runs([["$ ", Theme.theme_secondary], ["curl wttr.in/" + (WeatherState.location_name !== "" ? WeatherState.location_name.split(",")[0].replace(/ /g, "+") : "") + "?format=v2", Theme.fg_core]])
                font.family: Style.font_family
                font.pixelSize: root.text_px
            }

            Text {
                text: "[" + root.sub_names[root.sub] + "]"
                color: Style.text_strong
                font.family: Style.font_family
                font.pixelSize: root.text_px
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(root.lh, implicitHeight)
            textFormat: Text.StyledText
            elide: Text.ElideRight
            text: root.readout
            color: Style.text_fg
            font.family: Style.font_family
            font.pixelSize: root.text_px
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Column {
                id: axis_col
                width: root.axis_chars * root.glyph_w
                Repeater {
                    model: root.total_rows

                    Text {
                        required property int index
                        height: root.lh
                        text: root.axis_line(index)
                        color: root.rule
                        font.family: Style.font_family
                        font.pixelSize: root.text_px
                    }
                }
            }

            HourlyTrack {
                id: track
                anchors.left: axis_col.right
                anchors.leftMargin: 2
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                hour_cursor: root.hour_cursor
                sub: root.sub
                on_select: i => root.on_select(i)
                scroll_x: root.scroll_x
                on_scroll: x => { root.view_x = x; root.on_scroll(x); }
                paint: root.paint
                icon_row_h: root.lh * 2
                label_row_h: root.lh + 6

                underlay: [
                    // Reverse video on the text rows only; the graph rows get a faint tint so the trace keeps its colour.
                    Rectangle {
                        visible: root.hour_cursor >= 0 && root.hour_cursor < WeatherState.hours.length
                        x: track.left_of(root.hour_cursor)
                        width: track.hour_col_w
                        height: root.values_row * root.lh
                        color: Qt.alpha(Style.tab_active_bg, 0.14)
                    },
                    Rectangle {
                        visible: root.hour_cursor >= 0 && root.hour_cursor < WeatherState.hours.length
                        x: track.left_of(root.hour_cursor)
                        y: root.values_row * root.lh
                        width: track.hour_col_w
                        height: parent.height - y
                        color: Style.tab_active_bg
                    }
                ]

                cell: Item {
                    id: hour_col
                    required property var modelData
                    required property int index
                    readonly property bool selected: hour_col.index === root.hour_cursor

                    x: track.left_of(hour_col.index)
                    y: track.chart_h + 4
                    width: track.hour_col_w
                    height: track.icon_row_h + track.label_row_h

                    Text {
                        width: parent.width
                        height: track.icon_row_h
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.StyledText
                        color: hour_col.selected ? root.inverse : Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: root.text_px
                        lineHeight: root.lh
                        lineHeightMode: Text.FixedHeight
                        text: root.icon_text(hour_col.modelData, hour_col.selected)
                    }

                    Text {
                        y: track.icon_row_h
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: WeatherState.format_hour(new Date(hour_col.modelData.dt))
                        color: hour_col.selected ? root.inverse : Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: root.text_px
                    }
                }
            }
        }
    }
}
