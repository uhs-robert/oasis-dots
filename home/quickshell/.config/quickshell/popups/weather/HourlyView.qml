// home/quickshell/.config/quickshell/popups/weather/HourlyView.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../theme"
import "../../services"

// Full-range scrollable line chart. sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity.
// h/l move the hour cursor (auto-scrolling into view); H/L jump +-1 day, same hour.
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var sub_names: ["Temp", "Precip", "Wind", "UV", "Humid"]

    readonly property real readout_h: Math.max(18, readout_text.implicitHeight)

    readonly property var hour_colors: [Style.pal.yellow, Style.pal.blue, Style.pal.cyan, Style.pal.warning, Style.pal.bright_cyan]

    function scroll_to_cursor() {
        track.scroll_to_cursor();
    }

    function request_scroll() {
        track.request_scroll();
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0 || root.sub >= root.hour_colors.length) return;

        const values = hrs.map(track.value_of);
        let min_v, max_v;
        if (root.sub === 1 || root.sub === 4) { min_v = 0; max_v = 100; }
        else if (root.sub === 3) { min_v = 0; max_v = Math.max(12, Math.max(...values) + 1); }
        else {
            min_v = Math.min(...values);
            max_v = Math.max(...values);
            const pad = Math.max(2, (max_v - min_v) * 0.15);
            min_v -= pad;
            max_v += pad;
        }

        const top_pad = 20;
        const amount_px = Style.fs(-3);
        const bottom_pad = root.sub === 1 ? amount_px + 6 : 0;
        const plot_h = h - top_pad - bottom_pad;
        const y_of = v => top_pad + plot_h - ((v - min_v) / (max_v - min_v || 1)) * plot_h;
        const x_of = track.x_of;
        const color = root.hour_colors[root.sub];

        ctx.strokeStyle = Style.text_muted;
        ctx.globalAlpha = 0.25;
        ctx.lineWidth = 1;
        for (const b of track.day_boundaries) {
            const x = track.left_of(b.index);
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;
        ctx.fillStyle = Style.text_muted;
        ctx.font = (Style.fs(-2)) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (const b of track.day_boundaries) {
            ctx.fillText(b.label, track.left_of(b.index) + 3, 12);
        }

        if (root.sub === 1) {
            ctx.beginPath();
            ctx.moveTo(x_of(0), h - bottom_pad);
            for (let i = 0; i < hrs.length; i++) ctx.lineTo(x_of(i), y_of(hrs[i].pop));
            ctx.lineTo(x_of(hrs.length - 1), h - bottom_pad);
            ctx.closePath();
            ctx.fillStyle = Style.pal.blue;
            ctx.globalAlpha = 0.15;
            ctx.fill();
            ctx.globalAlpha = 1;
        }

        // Dimmer/dashed secondary line: feels-like for temp, gusts for wind.
        const secondary = root.sub === 0 ? hrs.map(r => r.feels) : root.sub === 2 ? hrs.map(r => r.wind_gusts) : null;
        if (secondary) {
            ctx.setLineDash([4, 3]);
            ctx.strokeStyle = Style.text_muted;
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                const x = x_of(i), y = y_of(secondary[i]);
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.stroke();
            ctx.setLineDash([]);
        }

        ctx.strokeStyle = color;
        ctx.lineWidth = 2.5;
        ctx.beginPath();
        for (let i = 0; i < hrs.length; i++) {
            const x = x_of(i), y = y_of(values[i]);
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.stroke();

        ctx.fillStyle = color;
        for (let i = 0; i < hrs.length; i++) {
            const x = x_of(i), y = y_of(values[i]);
            ctx.beginPath();
            ctx.arc(x, y, 3, 0, 2 * Math.PI);
            ctx.fill();
        }

        ctx.fillStyle = Style.pal.fg;
        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) {
            const v = values[i];
            const x = x_of(i), y = y_of(v);
            const label = root.sub === 3 ? v.toFixed(1) : Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
            ctx.fillText(label, x, Math.max(12, y - 8));
        }

        if (root.sub === 1) {
            ctx.fillStyle = Style.pal.blue;
            ctx.font = amount_px + "px \"" + Style.font_family + "\"";
            for (let i = 0; i < hrs.length; i++) ctx.fillText(hrs[i].precip.toFixed(hrs[i].precip < 1 ? 2 : 1), x_of(i), h - 4);
        }
    }

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]

    readonly property string readout: {
        const r = root.cursor_row;
        if (!r) return "";
        const parts = [WeatherState.format_hour(new Date(r.dt)), Math.round(r.temp) + "°" + WeatherState.unit_symbol(), r.pop + "% pop", r.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in"), r.cond];
        return parts.join(" · ");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Text {
            id: readout_text
            Layout.fillWidth: true
            Layout.preferredHeight: root.readout_h
            text: root.readout
            color: Style.pal.fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
            elide: Text.ElideRight
        }

        HourlyTrack {
            id: track
            Layout.fillWidth: true
            Layout.fillHeight: true
            // The shared view has always kept a 4px gap under the hour labels.
            Layout.bottomMargin: 4
            hour_cursor: root.hour_cursor
            sub: root.sub
            on_select: i => root.on_select(i)
            scroll_x: root.scroll_x
            on_scroll: x => root.on_scroll(x)
            paint: root.paint
            highlight: Component {
                Rectangle {
                    color: Style.selection_brackets.a > 0 ? Style.selection_bg : Style.pal.bg_surface
                    radius: Style.radius(3)

                    LockBrackets {}
                }
            }
            arrow_color: Style.pal.cyan
            label_color: Style.text_muted
            label_color_selected: Style.pal.secondary

            Rectangle {
                visible: root.hour_cursor >= 0 && root.hour_cursor < WeatherState.hours.length
                x: track.x_of(root.hour_cursor) - 0.5
                width: 1
                height: track.chart_h
                color: Style.pal.secondary
                opacity: 0.5
            }
        }
    }
}
