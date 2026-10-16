import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components.oasis as Oasis
import qs.theme
import qs.services

// Oasis Hourly: the series as a rolling dune ridge with wind-ripple lines in the sand; a palm stands on the cursor hour
// beside a floating value, and heat shimmers over the hot hours. Precip fills the dunes with water instead.
// sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity.
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property color sand: Theme.theme_secondary
    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]
    readonly property bool has_cursor: !!root.cursor_row

    // Sand for temperature and UV, water for rain, dusk blues for wind and humidity.
    readonly property color body_color: [root.sand, Theme.info, Theme.theme_primary_light, root.sand, Theme.theme_primary][root.sub]

    // Room above the ridge for the cursor's palm and its value pill.
    readonly property real top_pad: 68
    readonly property real amount_zone: root.sub === 1 ? 26 : 0
    readonly property real plot_h: track.chart_h - root.top_pad - root.amount_zone - 8
    readonly property real base_y: root.top_pad + root.plot_h
    // Full scale for the precip amount drops, in the forecast's own unit.
    readonly property real amount_full: WeatherState.metric ? 5 : 0.2
    // Heat shimmer starts at 82 F whatever the display unit.
    readonly property real hot_f: 82
    readonly property bool shimmer_live: track.visible && Popups.open_name === "weather"

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

    readonly property var hot_hours: {
        const out = [];
        if (root.sub !== 0) return out;
        const hrs = WeatherState.hours;
        for (let i = 0; i < hrs.length; i++) {
            if (WeatherState.temp_f(hrs[i].temp) >= root.hot_f) out.push(i);
        }
        return out;
    }

    function value_text(row) {
        const v = root.series(row);
        if (root.sub === 3) return v.toFixed(1);
        return Math.round(v) + (root.sub === 0 ? "°" : root.sub === 2 ? "" : "%");
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

    // The monotone cubic through (xs, ys) as a polyline every `step` px: smooth without overshooting between hours,
    // and a polyline lets the ripple lines wobble along it.
    function sample_ridge(xs, ys, step) {
        const n = xs.length;
        const out = [];
        if (n < 2) return out;
        const d = [], m = [];
        for (let i = 0; i < n - 1; i++) d.push((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]));
        m.push(d[0]);
        for (let i = 1; i < n - 1; i++) m.push(d[i - 1] * d[i] <= 0 ? 0 : 2 * d[i - 1] * d[i] / (d[i - 1] + d[i]));
        m.push(d[n - 2]);
        for (let i = 0; i < n - 1; i++) {
            const dx = xs[i + 1] - xs[i];
            for (let x = 0; x < dx; x += step) {
                const t = x / dx, t2 = t * t, t3 = t2 * t;
                out.push({
                    x: xs[i] + x,
                    y: (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * dx * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * dx * m[i + 1]
                });
            }
        }
        out.push({ x: xs[n - 1], y: ys[n - 1] });
        return out;
    }

    function trace_ridge(ctx, pts, dy, wobble, phase) {
        for (let i = 0; i < pts.length; i++) {
            const y = pts[i].y + dy + (wobble > 0 ? wobble * Math.sin(pts[i].x / 19 + phase) : 0);
            if (i === 0) ctx.moveTo(pts[i].x, y); else ctx.lineTo(pts[i].x, y);
        }
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const hair = Qt.alpha(Theme.theme_primary, 0.3);
        const fill_bottom = root.sub === 1 ? root.base_y + 2 : h;
        // Edge anchors run the ridge to both ends of the canvas.
        const xs = [0].concat(hrs.map((r, i) => track.x_of(i)), [w]);
        const vals = hrs.map(r => root.y_of(root.series(r)));
        const ys = [vals[0]].concat(vals, [vals[vals.length - 1]]);

        ctx.font = "600 " + Style.fs(-3) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (const b of track.day_boundaries) {
            const x = Math.round(track.left_of(b.index)) + 0.5;
            const rule = ctx.createLinearGradient(0, 22, 0, h);
            rule.addColorStop(0, "rgba(0,0,0,0)");
            rule.addColorStop(0.3, hair);
            rule.addColorStop(1, "rgba(0,0,0,0)");
            ctx.strokeStyle = rule;
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(x, 22);
            ctx.lineTo(x, h);
            ctx.stroke();
            ctx.fillStyle = Style.text_muted;
            ctx.fillText(b.label, x + 7, 14);
        }

        ctx.save();
        ctx.beginPath();
        ctx.rect(0, 0, w, fill_bottom);
        ctx.clip();

        // A paler dune behind the ridge, taken from earlier hours so it peeks over now and then.
        const back_ys = ys.map((y, i) => root.base_y - (root.base_y - ys[Math.max(0, i - 6)]) * 0.9 - 14);
        const back = root.sample_ridge(xs, back_ys, 4);
        ctx.beginPath();
        ctx.moveTo(0, fill_bottom);
        root.trace_ridge(ctx, back, 0, 0, 0);
        ctx.lineTo(w, fill_bottom);
        ctx.closePath();
        const back_fill = ctx.createLinearGradient(0, root.top_pad, 0, fill_bottom);
        back_fill.addColorStop(0, Qt.alpha(Theme.theme_primary, 0.26));
        back_fill.addColorStop(1, Qt.alpha(Theme.theme_primary, 0.04));
        ctx.fillStyle = back_fill;
        ctx.fill();

        const ridge = root.sample_ridge(xs, ys, 3);
        ctx.beginPath();
        ctx.moveTo(0, fill_bottom);
        root.trace_ridge(ctx, ridge, 0, 0, 0);
        ctx.lineTo(w, fill_bottom);
        ctx.closePath();
        // Opaque first, so the dune behind shows only where it clears the ridge.
        ctx.fillStyle = Qt.alpha(Style.frame_color, 1);
        ctx.fill();
        const fill = ctx.createLinearGradient(0, root.top_pad, 0, fill_bottom);
        fill.addColorStop(0, Qt.alpha(root.body_color, root.sub === 1 ? 0.5 : 0.46));
        fill.addColorStop(0.6, Qt.alpha(root.body_color, 0.16));
        fill.addColorStop(1, Qt.alpha(root.body_color, 0.03));
        ctx.fillStyle = fill;
        ctx.fill();

        // Wind-ripple lines fade out with depth.
        ctx.lineWidth = 1;
        ctx.lineCap = "round";
        for (let k = 1; k <= 4; k++) {
            ctx.strokeStyle = Qt.alpha(root.body_color, 0.2 - k * 0.035);
            ctx.beginPath();
            root.trace_ridge(ctx, ridge, k * 10, 1.6, k * 1.9);
            ctx.stroke();
        }
        ctx.restore();

        const secondary = hrs.map(r => root.secondary(r));
        if (secondary[0] !== null) {
            ctx.setLineDash([2, 4]);
            ctx.lineCap = "round";
            ctx.strokeStyle = Qt.alpha(Theme.fg_core, 0.5);
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            const sec_ys = secondary.map(v => root.y_of(v));
            root.trace_ridge(ctx, root.sample_ridge(xs, [sec_ys[0]].concat(sec_ys, [sec_ys[sec_ys.length - 1]]), 4), 0, 0, 0);
            ctx.stroke();
            ctx.setLineDash([]);
        }

        let crest = Qt.tint(root.body_color, Qt.alpha(Theme.fg_strong, 0.3));
        if (root.sub === 3) {
            crest = ctx.createLinearGradient(0, 0, w, 0);
            for (let i = 0; i < hrs.length; i++) crest.addColorStop(xs[i + 1] / w, WeatherState.uv_color(hrs[i].uv_index));
        }
        ctx.strokeStyle = crest;
        ctx.lineWidth = 2.5;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.beginPath();
        root.trace_ridge(ctx, ridge, 0, 0, 0);
        ctx.stroke();

        if (root.sub === 2) {
            // Spindrift: streaks above the crest, longer for faster wind and trailing downwind.
            ctx.lineWidth = 1.2;
            ctx.strokeStyle = Qt.alpha(Theme.theme_primary_light, 0.45);
            for (let i = 0; i < hrs.length; i++) {
                const len = 8 + Math.min(1, hrs[i].wind_speed / root.bounds.hi) * 30;
                const downwind = Math.sin(hrs[i].wind_dir * Math.PI / 180) > 0 ? -1 : 1;
                const x = track.x_of(i) - downwind * len / 2;
                for (let s = 0; s < 2; s++) {
                    const y = vals[i] - 21 - s * 5;
                    ctx.beginPath();
                    ctx.moveTo(x + downwind * s * 6, y);
                    ctx.lineTo(x + downwind * (len + s * 6), y);
                    ctx.stroke();
                }
            }
        }

        ctx.font = "500 " + Style.fs(-3) + "px \"" + Style.number_font + "\"";
        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) {
            if (i === root.hour_cursor) continue;
            ctx.fillStyle = root.sub === 3 ? WeatherState.uv_color(hrs[i].uv_index) : Theme.fg_core;
            ctx.fillText(root.value_text(hrs[i]), track.x_of(i), vals[i] - 8);
        }

        if (root.sub === 1) {
            const zone_bottom = h - 4;
            ctx.fillStyle = Qt.alpha(Theme.info, 0.8);
            for (let i = 0; i < hrs.length; i++) {
                if (hrs[i].precip <= 0) continue;
                const bh = Math.max(5, Math.min(1, hrs[i].precip / root.amount_full) * (root.amount_zone - 4));
                ctx.beginPath();
                ctx.roundedRect(track.x_of(i) - 3.5, zone_bottom - bh, 7, bh, 3.5, 3.5);
                ctx.fill();
            }
        }
    }

    readonly property string readout_time: root.has_cursor ? Qt.formatDate(new Date(root.cursor_row.dt), "ddd") + " " + WeatherState.format_hour(new Date(root.cursor_row.dt)) : ""

    readonly property string readout: {
        const r = root.cursor_row;
        if (!r) return "";
        return [Math.round(r.temp) + "°" + WeatherState.unit_symbol(), r.pop + "% pop", r.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in"), r.cond].join("  ·  ");
    }

    Connections {
        target: WeatherState
        function onMetricChanged() { track.request_paint(); }
    }

    // The cursor hour's value label hides behind its pill, so the canvas follows the cursor.
    onHour_cursorChanged: track.request_paint()

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 10

            Text {
                text: root.readout_time
                color: Style.text_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.readout
                color: Style.text_muted
                font.family: Style.number_font
                font.pixelSize: Style.fs(-2)
                font.features: { "tnum": 1 }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.25; color: Qt.alpha(root.sand, 0.35) }
                GradientStop { position: 0.75; color: Qt.alpha(root.sand, 0.35) }
                GradientStop { position: 1; color: "transparent" }
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

            cell: Component {
                Item {
                    id: hour_cell
                    required property var modelData
                    required property int index
                    readonly property bool selected: hour_cell.index === root.hour_cursor

                    x: track.left_of(hour_cell.index) + 2
                    y: track.chart_h + 4
                    width: track.hour_col_w - 4
                    height: track.icon_row_h + track.label_row_h

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.radius(6)
                        visible: hour_cell.selected
                        color: Style.selection_bg
                        border.width: 1
                        border.color: Qt.alpha(root.sand, 0.45)
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
                        opacity: hour_cell.selected ? 1 : 0.85
                    }

                    Text {
                        visible: root.sub === 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: (track.icon_row_h - height) / 2
                        text: "▲"
                        rotation: hour_cell.modelData.wind_dir
                        color: hour_cell.selected ? root.sand : Theme.theme_primary_light
                        font.pixelSize: Style.font_size
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: track.icon_row_h
                        text: WeatherState.format_hour(new Date(hour_cell.modelData.dt))
                        color: hour_cell.selected ? root.sand : Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                        font.weight: hour_cell.selected ? Font.DemiBold : Font.Medium
                    }
                }
            }

            Repeater {
                model: root.hot_hours

                Item {
                    id: haze
                    required property int modelData
                    readonly property real ridge_y: root.y_of(WeatherState.hours[haze.modelData].temp)

                    x: track.left_of(haze.modelData) + 8
                    y: haze.ridge_y - 54
                    width: track.hour_col_w - 16
                    height: 26
                    opacity: 0.4

                    SequentialAnimation on opacity {
                        running: root.shimmer_live
                        loops: Animation.Infinite
                        PauseAnimation { duration: (haze.modelData % 5) * 260 }
                        NumberAnimation { to: 0.08; duration: 1100; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.4; duration: 1100; easing.type: Easing.InOutSine }
                    }

                    SequentialAnimation on y {
                        running: root.shimmer_live
                        loops: Animation.Infinite
                        PauseAnimation { duration: (haze.modelData % 5) * 260 }
                        NumberAnimation { to: haze.ridge_y - 58; duration: 1100; easing.type: Easing.InOutSine }
                        NumberAnimation { to: haze.ridge_y - 54; duration: 1100; easing.type: Easing.InOutSine }
                    }

                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            ctx.lineWidth = 1.3;
                            ctx.lineCap = "round";
                            ctx.strokeStyle = Qt.alpha(Theme.theme_label, 0.65);
                            for (let k = 0; k < 3; k++) {
                                ctx.beginPath();
                                for (let x = 0; x <= width; x += 2) {
                                    const y = 4 + k * 8 + 2.2 * Math.sin(x / 5 + k * 1.4);
                                    if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                                }
                                ctx.stroke();
                            }
                        }
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
                    height: track.chart_h - cursor_layer.cy
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.alpha(root.sand, 0.5) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }

                Oasis.OasisPalm {
                    x: cursor_layer.cx - width / 2
                    y: cursor_layer.cy - height + 2
                    color: Theme.fg_strong
                }

                Rectangle {
                    id: pill
                    width: pill_row.implicitWidth + 18
                    height: pill_row.implicitHeight + 8
                    radius: height / 2
                    color: Qt.alpha(Theme.bg_mantle, 0.94)
                    border.width: 1
                    border.color: Qt.alpha(root.sand, 0.6)
                    x: Math.max(2, Math.min(track.hour_col_w * WeatherState.hours.length - pill.width - 2, cursor_layer.cx - pill.width / 2))
                    y: Math.max(20, cursor_layer.cy - 28 - pill.height - 3)

                    Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    Row {
                        id: pill_row
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.baseline: pill_detail.baseline
                            text: root.has_cursor ? root.value_text(root.cursor_row) : ""
                            color: root.sub === 3 && root.has_cursor ? WeatherState.uv_color(root.cursor_row.uv_index) : Style.text_strong
                            font.family: Style.number_font
                            font.pixelSize: Style.fs(0)
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }

                        Text {
                            id: pill_detail
                            visible: text !== ""
                            text: root.has_cursor ? root.detail_text(root.cursor_row) : ""
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
