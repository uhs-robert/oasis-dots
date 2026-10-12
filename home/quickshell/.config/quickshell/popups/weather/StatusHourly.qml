// home/quickshell/.config/quickshell/popups/weather/StatusHourly.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
import "Materia.js" as Materia

// An FF7 battle timeline: every hour is an ATB gauge filled to its value, turning to the Limit colour in the top fifth,
// with the white glove on the selected hour and its details in a battle-menu window above.
// sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity. h/l move the hour cursor (auto-scrolling into view).
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var sub_names: ["TEMP", "PRECIP", "WIND", "UV", "HUMID"]
    readonly property var sub_colors: [Style.pal.yellow, Theme.info, Style.pal.cyan, Style.pal.warning, Style.pal.bright_cyan]

    readonly property int gauge_w: 18
    readonly property int top_pad: 22
    readonly property real hot_from: 0.8
    readonly property int legend_h: 20
    // Heavy rain in the forecast's own unit, so amount bars read the same in mm and inches.
    readonly property real precip_full_scale: WeatherState.metric ? 5 : 0.2

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]
    readonly property var gauge_scale: root.scale_range(WeatherState.hours)

    function bottom_pad() {
        return root.sub === 1 ? Style.fs(-3) + 8 : 4;
    }

    function secondary_of(hrs) {
        return root.sub === 0 ? hrs.map(r => r.feels) : root.sub === 2 ? hrs.map(r => r.wind_gusts) : null;
    }

    // The dashed series shares the gauge scale, so feels-like and gusts beyond the main values stay on the plot.
    function scale_range(hrs) {
        if (hrs.length === 0) return { lo: 0, hi: 1 };
        const values = hrs.map(track.value_of).concat(root.secondary_of(hrs) || []);
        if (root.sub === 1 || root.sub === 4) return { lo: 0, hi: 100 };
        if (root.sub === 3) return { lo: 0, hi: Math.max(12, Math.max(...values) + 1) };
        let lo = Math.min(...values);
        let hi = Math.max(...values);
        if (root.sub === 2) return { lo: 0, hi: Math.max(10, hi * 1.1) };
        const pad = Math.max(2, (hi - lo) * 0.15);
        return { lo: lo - pad, hi: hi + pad };
    }

    function fill_frac(v) {
        return Math.max(0, Math.min(1, (v - root.gauge_scale.lo) / (root.gauge_scale.hi - root.gauge_scale.lo || 1)));
    }

    function gauge_h(chart_h) {
        return chart_h - root.top_pad - root.bottom_pad();
    }

    function fill_top(chart_h, v) {
        return root.top_pad + root.gauge_h(chart_h) * (1 - root.fill_frac(v));
    }

    function color_of(row) {
        return root.sub === 3 ? WeatherState.uv_color(row.uv_index) : root.sub_colors[root.sub];
    }

    function value_text(v) {
        if (root.sub === 3) return v.toFixed(1);
        return Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
    }

    function unit_text() {
        return ["°" + WeatherState.unit_symbol(), "% CHANCE", WeatherState.wind_unit(), "INDEX", "% RH"][root.sub].toUpperCase();
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

    function lit(color) {
        return Qt.tint(color, Qt.alpha(Theme.fg_strong, 0.55));
    }

    // One ATB gauge from the dark track up: the body in the sub's colour, anything past hot_from in the Limit colour.
    function draw_gauge(ctx, cx, bottom, gauge_h, frac, color) {
        const x = cx - root.gauge_w / 2;
        ctx.fillStyle = Theme.bg_crust;
        ctx.fillRect(x, bottom - gauge_h, root.gauge_w, gauge_h);
        const fill_h = Math.round((gauge_h - 2) * frac);
        const body_h = Math.min(fill_h, Math.round((gauge_h - 2) * root.hot_from));
        if (body_h > 0) {
            const grad = ctx.createLinearGradient(0, bottom - 1 - body_h, 0, bottom - 1);
            grad.addColorStop(0, root.lit(color));
            grad.addColorStop(1, color);
            ctx.fillStyle = grad;
            ctx.fillRect(x + 1, bottom - 1 - body_h, root.gauge_w - 2, body_h);
        }
        if (fill_h > body_h) {
            const hot_h = fill_h - body_h;
            const grad = ctx.createLinearGradient(0, bottom - 1 - fill_h, 0, bottom - 1 - body_h);
            grad.addColorStop(0, root.lit(Theme.theme_label));
            grad.addColorStop(1, Theme.theme_label);
            ctx.fillStyle = grad;
            ctx.fillRect(x + 1, bottom - 1 - fill_h, root.gauge_w - 2, hot_h);
        }
        ctx.fillStyle = Theme.bg_crust;
        ctx.globalAlpha = 0.35;
        for (let y = bottom - 1 - 6; y > bottom - 1 - fill_h; y -= 6) ctx.fillRect(x + 1, y, root.gauge_w - 2, 1);
        ctx.globalAlpha = 1;
        ctx.strokeStyle = Theme.fg_muted;
        ctx.lineWidth = 1;
        ctx.strokeRect(x + 0.5, bottom - gauge_h + 0.5, root.gauge_w - 1, gauge_h - 1);
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const values = hrs.map(track.value_of);
        const gauge_h = root.gauge_h(h);
        const bottom = root.top_pad + gauge_h;
        const x_of = track.x_of;

        ctx.lineWidth = 1;
        ctx.strokeStyle = Style.frame_border_color;
        ctx.globalAlpha = 0.45;
        for (const b of track.day_boundaries) {
            const x = Math.round(track.left_of(b.index)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;
        ctx.fillStyle = Style.text_dim;
        ctx.font = "800 " + Style.fs(-4) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (const b of track.day_boundaries) ctx.fillText(b.label, track.left_of(b.index) + 5, 13);

        for (let i = 0; i < hrs.length; i++) {
            root.draw_gauge(ctx, x_of(i), bottom, gauge_h, root.fill_frac(values[i]), root.color_of(hrs[i]));
            if (root.sub === 1 && hrs[i].precip > 0) {
                const bar_h = Math.max(2, Math.min(1, hrs[i].precip / root.precip_full_scale) * gauge_h);
                ctx.fillStyle = Theme.info;
                ctx.fillRect(x_of(i) + root.gauge_w / 2 + 3, bottom - bar_h, 4, bar_h);
            }
        }

        // Dashed line through the second series: feels-like for temp, gusts for wind.
        const secondary = root.secondary_of(hrs);
        if (secondary) {
            ctx.setLineDash([4, 3]);
            ctx.strokeStyle = Theme.fg_strong;
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                const y = root.fill_top(h, secondary[i]);
                if (i === 0) ctx.moveTo(x_of(i), y); else ctx.lineTo(x_of(i), y);
            }
            ctx.stroke();
            ctx.setLineDash([]);
        }

        ctx.font = "800 " + Style.fs(-3) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "center";
        ctx.lineWidth = 3;
        ctx.lineJoin = "round";
        ctx.strokeStyle = Theme.bg_crust;
        ctx.fillStyle = Theme.fg_strong;
        for (let i = 0; i < hrs.length; i++) {
            const y = Math.max(13, root.fill_top(h, values[i]) - 5);
            const label = root.value_text(values[i]);
            ctx.strokeText(label, x_of(i), y);
            ctx.fillText(label, x_of(i), y);
        }

        if (root.sub === 1) {
            ctx.fillStyle = Theme.info;
            ctx.font = "700 " + Style.fs(-4) + "px \"" + Style.font_family + "\"";
            for (let i = 0; i < hrs.length; i++) ctx.fillText(hrs[i].precip.toFixed(hrs[i].precip < 1 ? 2 : 1), x_of(i), h - 3);
        }
    }

    // The selected hour's readout, label then value, in the order of the shared line plus the sub's own fact.
    readonly property var stats: {
        const r = root.cursor_row;
        if (!r) return [];
        const base = [["TEMP", Math.round(r.temp) + "°" + WeatherState.unit_symbol()], ["POP", r.pop + "%"], ["RAIN", r.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in")]];
        const extra = [
            [["FEELS", Math.round(r.feels) + "°"]],
            [],
            [["WIND", Math.round(r.wind_speed) + " " + WeatherState.wind_unit() + " " + WeatherState.compass_label(r.wind_dir)], ["GUST", Math.round(r.wind_gusts)]],
            [["UV", r.uv_index.toFixed(1) + " " + WeatherState.uv_band(r.uv_index).label]],
            [["HUM", r.humidity + "%"]]
        ][root.sub];
        return base.concat(extra);
    }

    FontMetrics {
        id: stat_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-2)
        font.weight: Font.ExtraBold
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: readout_body.implicitHeight + 14

            StatusWindow {
                anchors.fill: parent
            }

            ColumnLayout {
                id: readout_body
                anchors.fill: parent
                anchors.margins: 7
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    MateriaOrb {
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                        color: root.cursor_row ? Materia.color(Style.materia_palette, WeatherState.weather_color_keys, root.cursor_row.code) : "transparent"
                    }

                    Text {
                        text: root.cursor_row ? WeatherState.format_hour(new Date(root.cursor_row.dt)) : "--"
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(2)
                        font.weight: Font.ExtraBold
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: root.cursor_row ? root.cursor_row.cond : ""
                        color: Theme.theme_primary_light
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-2)
                        font.weight: Font.DemiBold
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    // Wind's wider row wraps whatever the hour, so it reserves its second line up front to keep the track from jumping.
                    Layout.preferredHeight: root.sub === 2 || root.width < 330 ? stat_metrics.height * 2 + spacing : implicitHeight
                    spacing: 14

                    Repeater {
                        model: root.stats

                        Row {
                            id: stat
                            required property var modelData
                            spacing: 5

                            Text {
                                anchors.baseline: stat_value.baseline
                                text: stat.modelData[0]
                                color: Theme.theme_primary_light
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-5)
                                font.weight: Font.ExtraBold
                                font.letterSpacing: 1
                            }

                            Text {
                                id: stat_value
                                text: stat.modelData[1]
                                color: Theme.fg_strong
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-2)
                                font.weight: Font.ExtraBold
                            }
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
                id: legend
                x: 12
                y: 5
                width: parent.width - 24
                height: root.legend_h
                spacing: 8

                MateriaOrb {
                    Layout.preferredWidth: 11
                    Layout.preferredHeight: 11
                    color: root.sub_colors[root.sub]
                }

                Text {
                    text: root.sub_names[root.sub]
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.5
                }

                Text {
                    text: root.unit_text()
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    visible: root.secondary_name() !== ""
                    text: "- - " + root.secondary_name()
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1
                }

                Text {
                    visible: root.sub === 1
                    text: WeatherState.metric ? "MM / HR" : "IN / HR"
                    color: Theme.info
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1
                }
            }

            HourlyTrack {
                id: track
                x: 6
                y: root.legend_h + 6
                width: parent.width - 12
                height: parent.height - root.legend_h - 12
                icon_row_h: 28
                hour_cursor: root.hour_cursor
                sub: root.sub
                on_select: i => root.on_select(i)
                scroll_x: root.scroll_x
                on_scroll: x => root.on_scroll(x)
                paint: root.paint
                caps_day_labels: true
                arrow_color: Theme.theme_primary_light
                label_color: Style.text_dim
                label_color_selected: Theme.fg_strong
                label_bold_selected: true
                hidpi_icons: true

                underlay: [
                    Rectangle {
                        visible: root.hour_cursor >= 0 && root.hour_cursor < WeatherState.hours.length
                        x: track.left_of(root.hour_cursor)
                        width: track.hour_col_w
                        height: parent.height
                        radius: 3
                        color: Qt.alpha(Theme.fg_strong, 0.08)
                        border.width: 1
                        border.color: Qt.alpha(Style.frame_border_color, 0.5)
                    }
                ]

                HandCursor {
                    visible: !!root.cursor_row
                    width: 18
                    height: 11
                    x: track.x_of(root.hour_cursor) - root.gauge_w / 2 - width + 1
                    y: root.cursor_row ? Math.min(track.chart_h - height - 4, root.fill_top(track.chart_h, track.value_of(root.cursor_row)) - 1) : 0
                }
            }
        }
    }

    Connections {
        target: root
        function onGauge_scaleChanged() { track.request_paint(); }
    }
}
