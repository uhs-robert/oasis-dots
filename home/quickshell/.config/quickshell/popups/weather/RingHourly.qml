pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../components"
import "../../theme"
import "../../services"

// A hairline trace over dotted guides, with every hour read off a small ring gauge beneath it and the cursor hour framed by a reticle.
// sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity. h/l move the hour cursor (auto-scrolling into view).
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var channel_names: ["TEMP", "PRECIP", "WIND", "UV INDEX", "HUMIDITY"]

    readonly property color ink: Style.text_strong
    readonly property color accent: Style.text_primary
    readonly property real top_pad: 22
    readonly property real amount_px: Style.fs(-4)
    readonly property real bottom_pad: root.sub === 1 ? root.amount_px + 10 : 8
    // Heavy rain in the forecast's own unit, so amount bars read the same in mm and inches.
    readonly property real precip_full_scale: WeatherState.metric ? 5 : 0.2
    readonly property real gauge_size: 30
    readonly property real reticle_size: 52

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]
    readonly property bool has_cursor: !!root.cursor_row
    // The dashed trace shares the axis, so feels-like and gusts are part of the range.
    readonly property var scale: root.scale_range(WeatherState.hours, root.sub)
    // The wind gauge's full scale: the strongest gust in the forecast.
    readonly property real wind_cap: WeatherState.hours.length > 0 ? Math.max(1, ...WeatherState.hours.map(r => r.wind_gusts)) : 1

    function secondary_of(hrs, sub) {
        return sub === 0 ? hrs.map(r => r.feels) : sub === 2 ? hrs.map(r => r.wind_gusts) : null;
    }

    function scale_range(hrs, sub) {
        if (hrs.length === 0) return { lo: 0, hi: 1 };
        if (sub === 1 || sub === 4) return { lo: 0, hi: 100 };
        const primary = hrs.map(r => [r.temp, r.pop, r.wind_speed, r.uv_index, r.humidity][sub]);
        const values = primary.concat(root.secondary_of(hrs, sub) || []);
        if (sub === 3) return { lo: 0, hi: Math.max(12, Math.max(...values) + 1) };
        let lo = Math.min(...values);
        let hi = Math.max(...values);
        const pad = Math.max(2, (hi - lo) * 0.15);
        return { lo: lo - pad, hi: hi + pad };
    }

    function y_at(v, h) {
        const plot_h = h - root.top_pad - root.bottom_pad;
        return root.top_pad + plot_h - ((v - root.scale.lo) / (root.scale.hi - root.scale.lo || 1)) * plot_h;
    }

    // How far round its ring an hour's reading sits.
    function ring_fraction(row) {
        const f = root.sub === 0 ? WeatherState.temp_f(row.temp) / 100
            : root.sub === 1 ? row.pop / 100
            : root.sub === 2 ? row.wind_speed / root.wind_cap
            : root.sub === 3 ? row.uv_index / 12
            : row.humidity / 100;
        return Math.max(0, Math.min(1, f));
    }

    function value_text(v) {
        if (root.sub === 3) return v.toFixed(1);
        return String(Math.round(v));
    }

    function unit_text() {
        return ["°" + WeatherState.unit_symbol(), "% CHANCE", WeatherState.wind_unit().toUpperCase(), "UV", "% RH"][root.sub];
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

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const values = hrs.map(track.value_of);
        const x_of = track.x_of;
        const y_of = v => root.y_at(v, h);
        const base_y = h - root.bottom_pad;

        // Dotted guides at the quarter marks of the plot.
        ctx.strokeStyle = Style.hairline_dim;
        ctx.lineWidth = 1;
        ctx.setLineDash([1, 4]);
        for (let q = 0; q <= 4; q++) {
            const y = Math.round(root.top_pad + (base_y - root.top_pad) * q / 4) + 0.5;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(w, y);
            ctx.stroke();
        }
        ctx.setLineDash([]);

        // Hour ticks along the baseline, a taller one every six hours.
        ctx.strokeStyle = Style.hairline;
        for (let i = 0; i < hrs.length; i++) {
            const x = Math.round(x_of(i)) + 0.5;
            const major = hrs[i].hour % 6 === 0;
            ctx.globalAlpha = major ? 1 : 0.45;
            ctx.beginPath();
            ctx.moveTo(x, base_y);
            ctx.lineTo(x, base_y + (major ? 5 : 3));
            ctx.stroke();
        }
        ctx.globalAlpha = 1;

        ctx.strokeStyle = Style.hairline;
        for (const b of track.day_boundaries) {
            const x = Math.round(track.left_of(b.index)) + 0.5;
            ctx.setLineDash([2, 3]);
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
            ctx.setLineDash([]);
        }
        ctx.fillStyle = Style.text_muted;
        ctx.font = Style.fs(-4) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (const b of track.day_boundaries) ctx.fillText(b.label, track.left_of(b.index) + 5, 13);

        if (root.sub === 1) {
            ctx.fillStyle = root.accent;
            ctx.globalAlpha = 0.1;
            ctx.beginPath();
            ctx.moveTo(x_of(0), base_y);
            for (let i = 0; i < hrs.length; i++) ctx.lineTo(x_of(i), y_of(hrs[i].pop));
            ctx.lineTo(x_of(hrs.length - 1), base_y);
            ctx.closePath();
            ctx.fill();

            ctx.strokeStyle = root.accent;
            ctx.globalAlpha = 0.8;
            ctx.lineWidth = 1.5;
            for (let i = 0; i < hrs.length; i++) {
                if (hrs[i].precip <= 0) continue;
                const bar_h = Math.max(2, Math.min(1, hrs[i].precip / root.precip_full_scale) * 18);
                ctx.beginPath();
                ctx.moveTo(Math.round(x_of(i)) + 0.5, base_y);
                ctx.lineTo(Math.round(x_of(i)) + 0.5, base_y - bar_h);
                ctx.stroke();
            }
            ctx.globalAlpha = 1;
            ctx.lineWidth = 1;
        }

        const secondary = root.secondary_of(hrs, root.sub);
        if (secondary) {
            ctx.setLineDash([4, 3]);
            ctx.strokeStyle = Style.text_muted;
            ctx.lineWidth = 1.2;
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                if (i === 0) ctx.moveTo(x_of(i), y_of(secondary[i])); else ctx.lineTo(x_of(i), y_of(secondary[i]));
            }
            ctx.stroke();
            ctx.setLineDash([]);
        }

        ctx.strokeStyle = root.ink;
        ctx.lineJoin = "round";
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        for (let i = 0; i < hrs.length; i++) {
            if (i === 0) ctx.moveTo(x_of(i), y_of(values[i])); else ctx.lineTo(x_of(i), y_of(values[i]));
        }
        ctx.stroke();

        // Samples are small open rings; UV samples take their band's colour.
        ctx.fillStyle = Style.frame_color;
        ctx.lineWidth = 1.2;
        for (let i = 0; i < hrs.length; i++) {
            ctx.strokeStyle = root.sub === 3 ? WeatherState.uv_color(values[i]) : root.ink;
            ctx.beginPath();
            ctx.arc(x_of(i), y_of(values[i]), 2.5, 0, 2 * Math.PI);
            ctx.fill();
            ctx.stroke();
        }

        if (root.sub === 1) {
            ctx.fillStyle = root.accent;
            ctx.font = root.amount_px + "px \"" + Style.font_family + "\"";
            ctx.textAlign = "center";
            for (let i = 0; i < hrs.length; i++) ctx.fillText(hrs[i].precip.toFixed(hrs[i].precip < 1 ? 2 : 1), x_of(i), h - 1);
        }
    }

    // One hour's ring: a faint track lit clockwise from the top, the reading inside; wind adds a gust tick and a bearing marker.
    component HourRing: Item {
        id: ring
        required property var row
        readonly property real r: ring.width / 2 - 3
        readonly property color tone: root.sub === 3 ? WeatherState.uv_color(ring.row.uv_index) : root.ink

        function point(deg, radius) {
            const a = (deg - 90) * Math.PI / 180;
            return { x: ring.width / 2 + radius * Math.cos(a), y: ring.width / 2 + radius * Math.sin(a) };
        }

        function gust_tick() {
            const deg = 360 * Math.max(0, Math.min(1, ring.row.wind_gusts / root.wind_cap));
            const inner = ring.point(deg, ring.r - 3), outer = ring.point(deg, ring.r + 3);
            return "M" + inner.x.toFixed(2) + " " + inner.y.toFixed(2) + "L" + outer.x.toFixed(2) + " " + outer.y.toFixed(2);
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 1
                strokeColor: Qt.alpha(ring.tone, 0.2)
                fillColor: "transparent"
                PathAngleArc { centerX: ring.width / 2; centerY: ring.width / 2; radiusX: ring.r; radiusY: ring.r; startAngle: 0; sweepAngle: 360 }
            }

            ShapePath {
                strokeWidth: root.ring_fraction(ring.row) > 0 ? 2 : -1
                strokeColor: ring.tone
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.width / 2
                    radiusX: ring.r
                    radiusY: ring.r
                    startAngle: -90
                    sweepAngle: 360 * root.ring_fraction(ring.row)
                }
            }

            ShapePath {
                strokeWidth: root.sub === 2 ? 1.5 : -1
                strokeColor: root.accent
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathSvg { path: ring.gust_tick() }
            }
        }

        Text {
            anchors.centerIn: parent
            text: root.value_text(track.value_of(ring.row))
            color: ring.tone
            font.family: Style.number_font
            font.pixelSize: Style.fs(-4)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // Cursor readout in the header's caps-and-value style, with the channel's own reading set large beside it.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(readout_lines.implicitHeight, reading.implicitHeight)

            Column {
                id: readout_lines
                anchors.left: parent.left
                anchors.right: reading.visible ? reading.left : parent.right
                anchors.rightMargin: reading.visible ? 8 : 0
                spacing: 2

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: !root.has_cursor ? "NO SIGNAL" : WeatherState.format_hour(new Date(root.cursor_row.dt)).toUpperCase() + " · " + root.channel_names[root.sub] + " · " + root.unit_text()
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.letterSpacing: 2.5
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: !root.has_cursor ? "" : Math.round(root.cursor_row.temp) + "°" + WeatherState.unit_symbol() + " · " + root.cursor_row.pop + "% pop · " + root.cursor_row.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in") + " · " + root.cursor_row.cond
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                    font.letterSpacing: 0.5
                }
            }

            Column {
                id: reading
                visible: root.has_cursor
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    anchors.right: parent.right
                    text: root.has_cursor ? root.value_text(track.value_of(root.cursor_row)) : ""
                    color: Style.text_strong
                    font.family: Style.number_font
                    font.weight: Font.ExtraLight
                    font.pixelSize: Style.fs(6)
                }

                Text {
                    visible: root.secondary_name() !== "" && root.has_cursor
                    anchors.right: parent.right
                    text: !root.has_cursor ? "" : root.sub === 2 ? "G " + Math.round(root.cursor_row.wind_gusts) : root.sub === 0 ? "FEELS " + Math.round(root.cursor_row.feels) + "°" : ""
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.letterSpacing: 2
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Style.hairline }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        HourlyTrack {
            id: track
            Layout.fillWidth: true
            Layout.fillHeight: true
            icon_row_h: 70
            hour_cursor: root.hour_cursor
            sub: root.sub
            on_select: i => root.on_select(i)
            scroll_x: root.scroll_x
            on_scroll: x => root.on_scroll(x)
            paint: root.paint
            caps_day_labels: true

            cell: Component {
                Item {
                    id: hour_col
                    required property var modelData
                    required property int index
                    readonly property bool selected: hour_col.index === root.hour_cursor

                    x: track.left_of(hour_col.index)
                    y: track.chart_h + 4
                    width: track.hour_col_w
                    height: track.icon_row_h + track.label_row_h
                    opacity: hour_col.selected ? 1 : 0.75

                    HourRing {
                        x: (parent.width - width) / 2
                        y: root.reticle_size / 2 - height / 2
                        width: root.gauge_size
                        height: root.gauge_size
                        row: hour_col.modelData
                    }

                    Reticle {
                        visible: hour_col.selected
                        x: (parent.width - width) / 2
                        y: 0
                        width: root.reticle_size
                        height: root.reticle_size
                        color: Style.hairline
                    }

                    WeatherIcon {
                        visible: root.sub !== 2
                        x: (parent.width - width) / 2
                        y: root.reticle_size + 1
                        size: 16
                        code: hour_col.modelData.code
                        is_day: hour_col.modelData.is_day
                    }

                    Text {
                        visible: root.sub === 2
                        x: (parent.width - width) / 2
                        y: root.reticle_size + 1
                        text: WeatherState.compass_label(hour_col.modelData.wind_dir)
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-4)
                        font.letterSpacing: 1
                    }

                    Text {
                        x: (parent.width - width) / 2
                        y: track.icon_row_h
                        text: WeatherState.format_hour(new Date(hour_col.modelData.dt))
                        color: hour_col.selected ? Style.text_strong : Style.text_muted
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-4)
                    }
                }
            }

            // The cursor hour's sample, ringed on the trace with a hairline down to the baseline.
            Rectangle {
                visible: root.has_cursor
                x: track.x_of(root.hour_cursor) - 0.5
                width: 1
                height: track.chart_h
                color: Style.hairline_dim
            }

            Rectangle {
                visible: root.has_cursor
                readonly property real y_center: root.has_cursor ? root.y_at(track.value_of(root.cursor_row), track.chart_h) : 0
                width: 14
                height: 14
                radius: 7
                x: track.x_of(root.hour_cursor) - width / 2
                y: y_center - height / 2
                color: "transparent"
                border.width: 1
                border.color: root.ink
            }
        }
    }
}
