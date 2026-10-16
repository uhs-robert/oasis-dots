import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

// WeatherStar 4000+ "Hourly Graph": a bold line over a gridded blue panel, scrolling left to right.
// sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity.
// h/l move the hour cursor (auto-scrolling into view); H/L jump +-1 day, same hour.
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var sub_names: ["Temperature", "Precipitation", "Wind", "UV Index", "Humidity"]
    readonly property var line_colors: [Theme.theme_secondary, Theme.fg_strong, Style.pal.bright_cyan, Theme.theme_label, Theme.theme_primary_light]

    readonly property int axis_w: Style.px(34)
    readonly property int plot_top: 30
    readonly property int amount_px: Style.fs(-4)
    readonly property real readout_h: Math.max(18, readout_text.implicitHeight)
    readonly property int plot_bottom: root.sub === 1 ? root.amount_px + 6 : 0
    readonly property real plot_h: Math.max(1, track.chart_h - root.plot_top - root.plot_bottom)

    function secondary_of(row) {
        return root.sub === 0 ? row.feels : root.sub === 2 ? row.wind_gusts : null;
    }

    // Grid lines land on round values; the padded data range snaps outward to them, so the line fills most of the panel.
    readonly property var axis: {
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return { min: 0, max: 1, ticks: [0, 1] };
        if (root.sub === 1 || root.sub === 4) return { min: 0, max: 100, ticks: [0, 25, 50, 75, 100] };
        // Feels-like and gusts share the scale, so they count toward it or they would draw off the panel.
        const values = hrs.map(track.value_of).concat(hrs.map(root.secondary_of).filter(v => v !== null && v !== undefined));
        let lo = Math.min(...values), hi = Math.max(...values);
        const pad = Math.max(2, (hi - lo) * 0.15);
        lo -= pad;
        hi += pad;
        if (root.sub === 2) lo = Math.max(0, lo);
        if (root.sub === 3) {
            lo = 0;
            hi = Math.max(12, hi);
        }
        // Smallest round step that keeps the grid to five intervals once the ends snap outward to it.
        const steps = [1, 2, 5, 10, 20, 50, 100];
        const fits = s => Math.ceil(hi / s) - Math.floor(lo / s) <= 5;
        const step = steps.find(fits) || steps[steps.length - 1];
        const first = Math.floor(lo / step) * step;
        const last = Math.ceil(hi / step) * step;
        const ticks = [];
        for (let v = first; v <= last + step / 2; v += step) ticks.push(v);
        return { min: first, max: last, ticks: ticks };
    }

    function y_of(v) {
        const frac = (v - root.axis.min) / (root.axis.max - root.axis.min || 1);
        return root.plot_top + root.plot_h - frac * root.plot_h;
    }

    function tick_label(v) {
        return root.sub === 1 || root.sub === 4 ? v + "%" : root.sub === 0 ? v + "°" : "" + v;
    }

    function scroll_to_cursor() {
        track.scroll_to_cursor();
    }

    function request_scroll() {
        track.request_scroll();
    }

    // The channel's lettering is white-on-blue with a dark drop shadow; canvas text has no outline style, so offset a dark copy.
    function shadowed_text(ctx, text, x, y, color) {
        ctx.fillStyle = Theme.bg_shadow;
        ctx.fillText(text, x + 1, y + 1);
        ctx.fillStyle = color;
        ctx.fillText(text, x, y);
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0 || track.chart_h <= 0) return;

        const x_of = track.x_of;
        const color = root.line_colors[root.sub];
        const base_y = root.plot_top + root.plot_h;

        ctx.lineWidth = 1;
        ctx.strokeStyle = Theme.theme_primary_light;
        ctx.globalAlpha = 0.45;
        for (const t of root.axis.ticks) {
            const y = Math.round(root.y_of(t)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(w, y);
            ctx.stroke();
        }
        for (const b of track.day_boundaries) {
            const x = Math.round(track.left_of(b.index)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;

        ctx.font = Style.fs(-3) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (const b of track.day_boundaries) root.shadowed_text(ctx, b.label, track.left_of(b.index) + 4, 13, Theme.theme_primary_light);

        if (root.sub === 1) {
            ctx.beginPath();
            ctx.moveTo(x_of(0), base_y);
            for (let i = 0; i < hrs.length; i++) ctx.lineTo(x_of(i), root.y_of(hrs[i].pop));
            ctx.lineTo(x_of(hrs.length - 1), base_y);
            ctx.closePath();
            ctx.fillStyle = Theme.theme_primary_strong;
            ctx.globalAlpha = 0.35;
            ctx.fill();
            ctx.globalAlpha = 1;
        }

        // Dashed secondary line: feels-like for temp, gusts for wind.
        if (root.sub === 0 || root.sub === 2) {
            ctx.setLineDash([4, 3]);
            ctx.strokeStyle = Theme.theme_primary_light;
            ctx.lineWidth = 2;
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                const x = x_of(i), y = root.y_of(root.secondary_of(hrs[i]));
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.stroke();
            ctx.setLineDash([]);
        }

        ctx.lineJoin = "round";
        ctx.lineWidth = 5;
        ctx.strokeStyle = Theme.bg_shadow;
        ctx.beginPath();
        for (let i = 0; i < hrs.length; i++) {
            const x = x_of(i), y = root.y_of(track.value_of(hrs[i]));
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.stroke();
        ctx.lineWidth = 3;
        ctx.strokeStyle = color;
        ctx.stroke();

        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) {
            const v = track.value_of(hrs[i]);
            const label = root.sub === 3 ? v.toFixed(1) : Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
            root.shadowed_text(ctx, label, x_of(i), Math.max(root.plot_top - 2, root.y_of(v) - 8), Theme.fg_strong);
        }

        if (root.sub === 1) {
            ctx.font = root.amount_px + "px \"" + Style.font_family + "\"";
            for (let i = 0; i < hrs.length; i++) root.shadowed_text(ctx, hrs[i].precip.toFixed(hrs[i].precip < 1 ? 2 : 1), x_of(i), h - 3, Theme.theme_primary_light);
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

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Hourly Graph"
                color: Theme.theme_secondary
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                style: Text.Outline
                styleColor: Theme.bg_shadow
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: root.sub_names[root.sub] + (root.sub === 0 ? " (" + WeatherState.unit_symbol() + ")" : root.sub === 2 ? " (" + WeatherState.wind_unit() + ")" : "")
                color: root.line_colors[root.sub]
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
                style: Text.Outline
                styleColor: Theme.bg_shadow
            }
        }

        Text {
            id: readout_text
            Layout.fillWidth: true
            Layout.preferredHeight: root.readout_h
            text: root.readout
            color: Theme.fg_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
            style: Text.Outline
            styleColor: Theme.bg_shadow
            elide: Text.ElideRight
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            WsPanel {
                anchors.fill: parent
            }

            Item {
                id: axis_col
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 4
                anchors.topMargin: 4
                width: root.axis_w

                Repeater {
                    model: root.axis.ticks

                    Text {
                        required property real modelData
                        width: axis_col.width
                        horizontalAlignment: Text.AlignRight
                        y: root.y_of(modelData) - implicitHeight / 2
                        text: root.tick_label(modelData)
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                        style: Text.Outline
                        styleColor: Theme.bg_shadow
                    }
                }
            }

            HourlyTrack {
                id: track
                anchors.left: axis_col.right
                anchors.leftMargin: 4
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.top: parent.top
                anchors.topMargin: 4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                hour_cursor: root.hour_cursor
                sub: root.sub
                on_select: i => root.on_select(i)
                scroll_x: root.scroll_x
                on_scroll: x => root.on_scroll(x)
                paint: root.paint
                arrow_color: Style.pal.bright_cyan
                label_color: Theme.fg_strong
                label_color_selected: Theme.theme_secondary
                label_px: Style.fs(-3)
                label_outline: Theme.bg_shadow
                hidpi_icons: true
                underlay: [
                    Rectangle {
                        visible: root.hour_cursor >= 0 && root.hour_cursor < WeatherState.hours.length
                        x: track.left_of(root.hour_cursor)
                        width: track.hour_col_w
                        height: parent.height
                        color: Qt.alpha(Theme.theme_secondary, 0.14)
                        border.width: 2
                        border.color: Theme.theme_secondary
                    }
                ]
            }
        }
    }
}
