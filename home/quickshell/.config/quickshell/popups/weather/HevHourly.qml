import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services

// A Black Mesa lab oscilloscope: the hours as a scrolling phosphor trace on a graticule inside a monitor bezel, HEV amber numerals.
// sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity. h/l move the hour cursor (auto-scrolling into view).
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var channel_names: ["TEMP", "PRECIP", "WIND", "UV", "HUMID"]

    readonly property int legend_h: 18
    readonly property int bezel: 5
    readonly property color hl: Style.text_primary
    readonly property color hl_t: Style.text_muted
    readonly property color phosphor: Style.pal.green
    readonly property color rain: Theme.info
    readonly property real readout_h: Math.max(26, readout_row.implicitHeight)

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]

    // Heavy rain in the forecast's own unit, so amount bars read the same in mm and inches.
    readonly property real precip_full_scale: WeatherState.metric ? 5 : 0.2

    function value_text(v) {
        if (root.sub === 3) return v.toFixed(1);
        return Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
    }

    function unit_text() {
        return ["°" + WeatherState.unit_symbol(), "% CHANCE", WeatherState.wind_unit(), "UV INDEX", "% RH"][root.sub];
    }

    function secondary_name() {
        return root.sub === 0 ? "FEELS" : root.sub === 2 ? "GUSTS" : "";
    }

    function scroll_to_cursor() {
        track.scroll_to_cursor();
    }

    function request_scroll() {
        track.request_scroll();
    }

    function secondary_of(hrs) {
        return root.sub === 0 ? hrs.map(r => r.feels) : root.sub === 2 ? hrs.map(r => r.wind_gusts) : null;
    }

    // The dashed trace shares the scale, so gusts above the speeds stay on screen.
    function scale_range(hrs) {
        const values = hrs.map(track.value_of).concat(root.secondary_of(hrs) || []);
        if (root.sub === 1 || root.sub === 4) return { lo: 0, hi: 100 };
        if (root.sub === 3) return { lo: 0, hi: Math.max(12, Math.max(...values) + 1) };
        let lo = Math.min(...values);
        let hi = Math.max(...values);
        const pad = Math.max(2, (hi - lo) * 0.15);
        return { lo: lo - pad, hi: hi + pad };
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const values = hrs.map(track.value_of);
        const range = root.scale_range(hrs);
        const top_pad = 20;
        const amount_px = Style.fs(-3);
        const bottom_pad = root.sub === 1 ? amount_px + 8 : 4;
        const plot_h = h - top_pad - bottom_pad;
        const y_of = v => top_pad + plot_h - ((v - range.lo) / (range.hi - range.lo || 1)) * plot_h;
        const x_of = track.x_of;

        // Graticule: hour columns, a heavier line every six hours, four horizontal divisions with tick marks on the centre line.
        ctx.lineWidth = 1;
        ctx.strokeStyle = root.hl;
        for (let i = 0; i <= hrs.length; i++) {
            const x = Math.round(i * track.hour_col_w) + 0.5;
            ctx.globalAlpha = i < hrs.length && hrs[i].hour % 6 === 0 ? 0.2 : 0.08;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        for (let d = 0; d <= 4; d++) {
            const y = Math.round(top_pad + plot_h * d / 4) + 0.5;
            ctx.globalAlpha = d === 2 ? 0.28 : 0.1;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(w, y);
            ctx.stroke();
        }
        ctx.globalAlpha = 0.28;
        const mid_y = Math.round(top_pad + plot_h / 2);
        for (let i = 0; i < hrs.length * 4; i++) {
            const x = Math.round(i * track.hour_col_w / 4) + 0.5;
            ctx.beginPath();
            ctx.moveTo(x, mid_y - (i % 4 === 0 ? 4 : 2));
            ctx.lineTo(x, mid_y + (i % 4 === 0 ? 5 : 3));
            ctx.stroke();
        }

        ctx.globalAlpha = 0.6;
        for (const b of track.day_boundaries) {
            const x = Math.round(track.left_of(b.index)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;
        ctx.fillStyle = root.hl_t;
        ctx.font = "bold " + Style.fs(-5) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (const b of track.day_boundaries) ctx.fillText(b.label, track.left_of(b.index) + 4, 12);

        if (root.sub === 1) {
            ctx.fillStyle = root.rain;
            for (let i = 0; i < hrs.length; i++) {
                if (hrs[i].precip <= 0) continue;
                const bar_h = Math.max(1, Math.min(1, hrs[i].precip / root.precip_full_scale) * 14);
                ctx.globalAlpha = 0.55;
                ctx.fillRect(x_of(i) - 8, h - bottom_pad - bar_h, 16, bar_h);
            }
            ctx.globalAlpha = 0.14;
            ctx.beginPath();
            ctx.moveTo(x_of(0), h - bottom_pad);
            for (let i = 0; i < hrs.length; i++) ctx.lineTo(x_of(i), y_of(hrs[i].pop));
            ctx.lineTo(x_of(hrs.length - 1), h - bottom_pad);
            ctx.closePath();
            ctx.fillStyle = root.phosphor;
            ctx.fill();
            ctx.globalAlpha = 1;
        }

        // Dashed second trace: feels-like for temp, gusts for wind.
        const secondary = root.secondary_of(hrs);
        if (secondary) {
            ctx.setLineDash([4, 3]);
            ctx.strokeStyle = root.hl;
            ctx.globalAlpha = 0.6;
            ctx.lineWidth = 1.2;
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                if (i === 0) ctx.moveTo(x_of(i), y_of(secondary[i])); else ctx.lineTo(x_of(i), y_of(secondary[i]));
            }
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.globalAlpha = 1;
        }

        // Phosphor glow: the same path wide and faint, then narrow and bright.
        ctx.strokeStyle = root.phosphor;
        ctx.lineJoin = "round";
        for (const pass of [[7, 0.12], [4, 0.25], [1.6, 1]]) {
            ctx.lineWidth = pass[0];
            ctx.globalAlpha = pass[1];
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                if (i === 0) ctx.moveTo(x_of(i), y_of(values[i])); else ctx.lineTo(x_of(i), y_of(values[i]));
            }
            ctx.stroke();
        }
        ctx.globalAlpha = 1;

        ctx.fillStyle = root.phosphor;
        for (let i = 0; i < hrs.length; i++) ctx.fillRect(x_of(i) - 1.5, y_of(values[i]) - 1.5, 3, 3);

        ctx.fillStyle = root.hl;
        ctx.font = "bold " + Style.fs(-3) + "px \"" + Style.number_font + "\"";
        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) ctx.fillText(root.value_text(values[i]), x_of(i), Math.max(12, y_of(values[i]) - 8));

        if (root.sub === 1) {
            ctx.fillStyle = root.rain;
            ctx.font = amount_px + "px \"" + Style.number_font + "\"";
            for (let i = 0; i < hrs.length; i++) ctx.fillText(hrs[i].precip.toFixed(hrs[i].precip < 1 ? 2 : 1), x_of(i), h - 3);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // Cursor readout: the hour in HUD numerals, the shared line's details, the channel's value at the cursor.
        RowLayout {
            id: readout_row
            Layout.fillWidth: true
            Layout.preferredHeight: root.readout_h
            spacing: 8

            Text {
                text: root.cursor_row ? WeatherState.format_hour(new Date(root.cursor_row.dt)) : "--"
                color: root.hl
                font.family: Style.number_font
                font.pixelSize: Style.fs(6)
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: {
                    const r = root.cursor_row;
                    if (!r) return "";
                    return [Math.round(r.temp) + "°" + WeatherState.unit_symbol(), r.pop + "% pop", r.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in"), r.cond].join(" · ");
                }
                color: root.hl_t
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            Text {
                visible: !!root.cursor_row && root.sub !== 0
                text: root.cursor_row ? root.value_text(track.value_of(root.cursor_row)) : ""
                color: root.phosphor
                font.family: Style.number_font
                font.pixelSize: Style.fs(6)
                font.bold: true
            }
        }

        // The monitor: a bezel around the legend strip, the scrolling screen and the hour labels beneath it.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.bg_crust
            border.width: 1
            border.color: Style.hairline

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                color: "transparent"
                border.width: 1
                border.color: Style.hairline_dim
            }

            Item {
                anchors.fill: parent
                anchors.margins: root.bezel

                RowLayout {
                    id: legend
                    width: parent.width
                    height: root.legend_h
                    spacing: 6

                    Rectangle {
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        color: root.phosphor
                    }

                    Text {
                        text: "CH1 " + root.channel_names[root.sub]
                        color: root.hl
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    Text {
                        text: root.unit_text()
                        color: root.hl_t
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: root.secondary_name() !== ""
                        text: "- - " + root.secondary_name()
                        color: root.hl_t
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                        font.letterSpacing: 1.5
                    }

                    Text {
                        visible: root.sub === 1
                        text: WeatherState.metric ? "MM / HR" : "IN / HR"
                        color: root.rain
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                        font.letterSpacing: 1.5
                    }
                }

                HourlyTrack {
                    id: track
                    y: root.legend_h
                    width: parent.width
                    height: parent.height - root.legend_h
                    icon_row_h: 28
                    hour_cursor: root.hour_cursor
                    sub: root.sub
                    on_select: i => root.on_select(i)
                    scroll_x: root.scroll_x
                    on_scroll: x => root.on_scroll(x)
                    paint: root.paint
                    caps_day_labels: true
                    highlight: Component {
                        Rectangle {
                            color: Style.selection_bg
                            border.width: 1
                            border.color: Style.selection_border
                        }
                    }
                    arrow_color: root.hl
                    label_color: root.hl_t
                    label_color_selected: root.hl
                    label_font_family: Style.number_font
                    label_px: Style.fs(-3)
                    label_bold_selected: true

                    Rectangle {
                        visible: root.hour_cursor >= 0 && root.hour_cursor < WeatherState.hours.length
                        x: track.left_of(root.hour_cursor)
                        width: track.hour_col_w
                        height: track.chart_h
                        color: Style.selection_bg
                        border.width: 1
                        border.color: Style.selection_border
                    }

                    Rectangle {
                        y: track.chart_h
                        width: parent.width
                        height: 1
                        color: Style.hairline
                    }
                }
            }
        }
    }
}
