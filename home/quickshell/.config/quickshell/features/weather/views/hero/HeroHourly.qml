import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.styles.modern.widgets as Modern
import qs.theme
import qs.features.weather
import qs.features.weather.views.shared

// Modern Hourly: a smooth gradient area chart with a pill tooltip riding the cursor hour, over a row of hour pills.
// sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity.
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var sub_colors: [Theme.theme_primary, Theme.info, Theme.theme_secondary, Theme.theme_label, Theme.theme_primary_light]
    readonly property color accent: root.sub_colors[root.sub]
    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]
    readonly property bool has_cursor: !!root.cursor_row

    readonly property real top_pad: 34
    readonly property real amount_zone: root.sub === 1 ? 26 : 0
    readonly property real plot_h: track.chart_h - root.top_pad - root.amount_zone - 6
    // Full scale for the precip amount bars, in the forecast's own unit.
    readonly property real amount_full: WeatherState.metric ? 5 : 0.2

    function series(row) {
        return [row.temp, row.pop, row.wind_speed, row.uv_index, row.humidity][root.sub];
    }

    // Secondary series share the primary axis, so they widen the range.
    function secondary(row) {
        return root.sub === 0 ? row.feels : root.sub === 2 ? row.wind_gusts : null;
    }

    readonly property var bounds: {
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return { lo: 0, hi: 1 };
        if (root.sub === 1 || root.sub === 4) return { lo: 0, hi: 100 };
        const all = [];
        for (const r of hrs) {
            all.push(root.series(r));
            const s = root.secondary(r);
            if (s !== null) all.push(s);
        }
        const lo = Math.min(...all), hi = Math.max(...all);
        if (root.sub === 3) return { lo: 0, hi: Math.max(12, hi + 1) };
        if (root.sub === 2) return { lo: 0, hi: Math.max(10, hi * 1.1) };
        const pad = Math.max(2, (hi - lo) * 0.15);
        return { lo: lo - pad, hi: hi + pad };
    }

    function y_of(v) {
        return root.top_pad + root.plot_h - ((v - root.bounds.lo) / (root.bounds.hi - root.bounds.lo || 1)) * root.plot_h;
    }

    function unit_suffix() {
        return root.sub === 0 ? "°" : root.sub === 1 || root.sub === 4 ? "%" : root.sub === 2 ? " " + WeatherState.wind_unit() : "";
    }

    function value_text(row) {
        const v = root.series(row);
        if (root.sub === 3) return v.toFixed(1);
        return Math.round(v) + (root.sub === 2 ? "" : root.unit_suffix());
    }

    function detail_text(row) {
        if (root.sub === 0) return "feels " + Math.round(row.feels) + "°";
        if (root.sub === 1) return row.precip.toFixed(row.precip < 1 ? 2 : 1) + (WeatherState.metric ? " mm" : " in");
        if (root.sub === 2) return WeatherState.wind_unit() + " · gust " + Math.round(row.wind_gusts) + " " + WeatherState.compass_label(row.wind_dir);
        if (root.sub === 3) return WeatherState.uv_band(row.uv_index).label;
        return "";
    }

    function scroll_to_cursor() {
        track.scroll_to_cursor();
    }

    function request_scroll() {
        track.request_scroll();
    }

    // Monotone cubic through (xs, ys): smooth without overshooting between hours.
    function trace_curve(ctx, xs, ys, start_with_move) {
        const n = xs.length;
        if (n === 0) return;
        if (start_with_move) ctx.moveTo(xs[0], ys[0]);
        else ctx.lineTo(xs[0], ys[0]);
        if (n === 1) return;
        const d = [], m = [];
        for (let i = 0; i < n - 1; i++) d.push((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]));
        m.push(d[0]);
        for (let i = 1; i < n - 1; i++) m.push(d[i - 1] * d[i] <= 0 ? 0 : 2 * d[i - 1] * d[i] / (d[i - 1] + d[i]));
        m.push(d[n - 2]);
        for (let i = 0; i < n - 1; i++) {
            const dx = (xs[i + 1] - xs[i]) / 3;
            ctx.bezierCurveTo(xs[i] + dx, ys[i] + m[i] * dx, xs[i + 1] - dx, ys[i + 1] - m[i + 1] * dx, xs[i + 1], ys[i + 1]);
        }
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const xs = hrs.map((r, i) => track.x_of(i));
        const base_y = root.top_pad + root.plot_h;

        ctx.lineWidth = 1;
        ctx.strokeStyle = Qt.alpha(Theme.fg_strong, 0.07);
        for (let g = 0; g <= 3; g++) {
            const gy = Math.round(root.top_pad + root.plot_h * g / 3) + 0.5;
            ctx.beginPath();
            ctx.moveTo(0, gy);
            ctx.lineTo(w, gy);
            ctx.stroke();
        }

        ctx.font = "600 " + Style.fs(-3) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        ctx.fillStyle = Style.text_muted;
        for (const b of track.day_boundaries) {
            const x = track.left_of(b.index);
            ctx.strokeStyle = Qt.alpha(Theme.fg_strong, 0.1);
            ctx.beginPath();
            ctx.moveTo(x + 0.5, 20);
            ctx.lineTo(x + 0.5, h);
            ctx.stroke();
            ctx.fillText(b.label, x + 8, 14);
        }

        const ys = hrs.map(r => root.y_of(root.series(r)));

        const fill = ctx.createLinearGradient(0, root.top_pad, 0, base_y);
        fill.addColorStop(0, Qt.alpha(root.accent, 0.5));
        fill.addColorStop(1, Qt.alpha(root.accent, 0));
        ctx.beginPath();
        ctx.moveTo(xs[0], base_y);
        root.trace_curve(ctx, xs, ys, false);
        ctx.lineTo(xs[xs.length - 1], base_y);
        ctx.closePath();
        ctx.fillStyle = fill;
        ctx.fill();

        const sec = hrs.map(r => root.secondary(r));
        if (sec[0] !== null) {
            ctx.setLineDash([2, 4]);
            ctx.lineCap = "round";
            ctx.strokeStyle = Qt.alpha(Theme.fg_strong, 0.5);
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            root.trace_curve(ctx, xs, sec.map(v => root.y_of(v)), true);
            ctx.stroke();
            ctx.setLineDash([]);
        }

        const stroke = ctx.createLinearGradient(0, root.top_pad, 0, base_y);
        stroke.addColorStop(0, Qt.tint(root.accent, Qt.alpha(Theme.fg_strong, 0.25)));
        stroke.addColorStop(1, root.accent);
        ctx.strokeStyle = stroke;
        ctx.lineWidth = 2.5;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.beginPath();
        root.trace_curve(ctx, xs, ys, true);
        ctx.stroke();

        if (root.sub === 1) {
            const bar_w = 12;
            const zone_bottom = h - 4;
            ctx.fillStyle = Qt.alpha(Theme.info, 0.75);
            for (let i = 0; i < hrs.length; i++) {
                const frac = Math.min(1, hrs[i].precip / root.amount_full);
                if (hrs[i].precip <= 0) continue;
                const bh = Math.max(4, frac * (root.amount_zone - 4));
                ctx.beginPath();
                ctx.roundedRect(xs[i] - bar_w / 2, zone_bottom - bh, bar_w, bh, 4, 4);
                ctx.fill();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 8

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.has_cursor ? Qt.formatDate(new Date(root.cursor_row.dt), "ddd") + " " + WeatherState.format_hour(new Date(root.cursor_row.dt)) + "  ·  " + root.cursor_row.cond : ""
                color: Style.text_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                font.weight: Font.DemiBold
            }

            Text {
                text: root.has_cursor ? Math.round(root.cursor_row.temp) + "°" + WeatherState.unit_symbol() + "  ·  " + root.cursor_row.pop + "%  ·  " + root.cursor_row.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in") : ""
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
                font.features: { "tnum": 1 }
            }
        }

        HourlyTrack {
            id: track
            Layout.fillWidth: true
            Layout.fillHeight: true
            // The shared view keeps a 4px gap under the hour labels.
            Layout.bottomMargin: 4
            hour_cursor: root.hour_cursor
            sub: root.sub
            on_select: i => root.on_select(i)
            scroll_x: root.scroll_x
            on_scroll: x => root.on_scroll(x)
            paint: root.paint

            Connections {
                target: WeatherState
                function onMetricChanged() { track.request_paint(); }
            }

            cell: Component {
                Item {
                    id: hour_cell
                    required property var modelData
                    required property int index
                    readonly property bool selected: hour_cell.index === root.hour_cursor

                    x: track.left_of(hour_cell.index) + 3
                    y: track.chart_h + 4
                    width: track.hour_col_w - 6
                    height: track.icon_row_h + track.label_row_h

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.radius(8)
                        color: hour_cell.selected ? "transparent" : Qt.alpha(Theme.fg_strong, 0.04)
                        gradient: hour_cell.selected ? pill_gradient : null

                        Gradient {
                            id: pill_gradient
                            GradientStop { position: 0; color: Style.selection_shade.a > 0 ? Style.selection_shade : Style.selection_bg }
                            GradientStop { position: 1; color: Style.selection_bg }
                        }
                    }

                    Image {
                        visible: root.sub !== 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 1
                        width: track.icon_row_h - 2
                        height: width
                        readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                        sourceSize.width: Math.ceil(width * 2 * dpr)
                        sourceSize.height: Math.ceil(height * 2 * dpr)
                        source: WeatherState.icon_source(hour_cell.modelData.code, hour_cell.modelData.is_day)
                        smooth: true
                    }

                    Text {
                        visible: root.sub === 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: (track.icon_row_h - height) / 2
                        text: "▲"
                        rotation: hour_cell.modelData.wind_dir
                        color: hour_cell.selected ? Style.selection_fg : root.accent
                        font.pixelSize: Style.font_size
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: track.icon_row_h
                        text: WeatherState.format_hour(new Date(hour_cell.modelData.dt))
                        color: hour_cell.selected ? Style.selection_fg : Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                        font.weight: hour_cell.selected ? Font.DemiBold : Font.Normal
                    }
                }
            }

            Item {
                id: cursor_layer
                visible: root.has_cursor
                readonly property real cx: track.x_of(root.hour_cursor)
                readonly property real cy: root.has_cursor ? root.y_of(root.series(root.cursor_row)) : 0

                Rectangle {
                    x: cursor_layer.cx - 0.5
                    y: cursor_layer.cy
                    width: 1
                    height: root.top_pad + root.plot_h - cursor_layer.cy
                    color: Qt.alpha(root.accent, 0.55)
                }

                Rectangle {
                    x: cursor_layer.cx - 9
                    y: cursor_layer.cy - 9
                    width: 18
                    height: 18
                    radius: 9
                    color: Qt.alpha(root.accent, 0.25)
                }

                Rectangle {
                    x: cursor_layer.cx - 5
                    y: cursor_layer.cy - 5
                    width: 10
                    height: 10
                    radius: 5
                    color: Style.text_strong
                    border.width: 3
                    border.color: root.accent
                }

                Modern.CardSurface {
                    id: tooltip
                    selected: true
                    radius: height / 2
                    width: tip_row.implicitWidth + 22
                    height: tip_row.implicitHeight + 10
                    readonly property bool below: cursor_layer.cy - tooltip.height - 12 < 18
                    x: Math.max(2, Math.min(track.hour_col_w * WeatherState.hours.length - tooltip.width - 2, cursor_layer.cx - tooltip.width / 2))
                    y: tooltip.below ? cursor_layer.cy + 14 : cursor_layer.cy - tooltip.height - 12

                    Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    RowLayout {
                        id: tip_row
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            Layout.alignment: Qt.AlignBaseline
                            text: root.has_cursor ? root.value_text(root.cursor_row) : ""
                            color: Style.text_strong
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(0)
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }

                        Text {
                            id: tip_detail
                            Layout.alignment: Qt.AlignBaseline
                            text: root.has_cursor ? root.detail_text(root.cursor_row) : ""
                            visible: text !== ""
                            color: Style.text_dim
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                        }
                    }
                }
            }
        }
    }
}
