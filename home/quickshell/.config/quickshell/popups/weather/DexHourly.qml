import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
import "PixelArt.js" as PixelArt

// The Pokégear radio: each hour a column of signal bars on a tuner dial that scrolls past a fixed needle, the hour's reading in the readout above.
// sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity. h/l move the hour cursor (auto-scrolling into view).
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var channel_names: ["TEMP", "RAIN", "WIND", "UV", "HUM"]
    readonly property var shades: Style.pixel_shades
    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]
    readonly property bool cursor_valid: !!root.cursor_row

    // Heavy rain in the forecast's own unit, so amount bars read the same in mm and inches.
    readonly property real precip_full_scale: WeatherState.metric ? 5 : 0.2
    readonly property string precip_unit: WeatherState.metric ? "MM" : "IN"

    // Signal bars are stacked 4px segments with a 2px gap.
    readonly property int seg_h: 4
    readonly property int seg_step: 6
    readonly property int bar_w: 32
    readonly property int top_pad: 24
    readonly property int dial_h: 14
    readonly property int amount_h: 16

    function secondary_of(hrs) {
        return root.sub === 0 ? hrs.map(r => r.feels) : root.sub === 2 ? hrs.map(r => r.wind_gusts) : null;
    }

    // The feels-like and gust marks share the scale, so they stay on the plot.
    function scale_range(hrs) {
        const values = hrs.map(track.value_of).concat(root.secondary_of(hrs) || []);
        if (root.sub === 1 || root.sub === 4) return { lo: 0, hi: 100 };
        if (root.sub === 3) return { lo: 0, hi: Math.max(12, Math.max(...values) + 1) };
        if (root.sub === 2) return { lo: 0, hi: Math.max(10, Math.max(...values) * 1.1) };
        const lo = Math.min(...values);
        const hi = Math.max(...values);
        const pad = Math.max(2, (hi - lo) * 0.15);
        return { lo: lo - pad, hi: hi + pad };
    }

    function value_text(v) {
        return root.sub === 3 ? v.toFixed(1) : String(Math.round(v));
    }

    function base_y(h) {
        return h - root.dial_h - (root.sub === 1 ? root.amount_h : 0) - 2;
    }

    // Lit segments for a value, whole segments so the bars stay on the LCD grid.
    function lit_of(v, range, h) {
        const max_n = Math.max(1, Math.floor((root.base_y(h) - root.top_pad) / root.seg_step));
        // Temperature and wind keep a base segment so a bar always shows; the zero-based scales may go dark.
        const floor_n = root.sub === 0 || root.sub === 2 ? 1 : 0;
        return Math.max(floor_n, Math.min(max_n, Math.round((v - range.lo) / (range.hi - range.lo || 1) * max_n)));
    }

    function level_y(n, h) {
        return root.base_y(h) - n * root.seg_step;
    }

    function scroll_to_cursor() {
        track.scroll_to_cursor();
    }

    function request_scroll() {
        track.request_scroll();
    }

    // Segment rows of one bar: unselected bodies are a 4px checker, the top segment and the whole selected bar are solid.
    function bar_rects(ctx, x, base, n, selected) {
        if (n < 1) return;
        const shade_body = root.shades[2];
        const shade_alt = root.shades[1];
        const shade_top = root.shades[3];
        ctx.fillStyle = String(shade_alt);
        ctx.beginPath();
        for (let k = 0; k < n; k++) {
            const y = base - (k + 1) * root.seg_step + 2;
            if (selected || k === n - 1) continue;
            for (let c = 0; c < root.bar_w / 4; c++) if ((c + k) % 2) ctx.rect(x + c * 4, y, 4, root.seg_h);
        }
        ctx.fill();
        ctx.fillStyle = String(shade_body);
        ctx.beginPath();
        for (let k = 0; k < n; k++) {
            const y = base - (k + 1) * root.seg_step + 2;
            if (selected || k === n - 1) continue;
            for (let c = 0; c < root.bar_w / 4; c++) if ((c + k) % 2 === 0) ctx.rect(x + c * 4, y, 4, root.seg_h);
        }
        ctx.fill();
        ctx.fillStyle = String(shade_top);
        ctx.beginPath();
        if (selected) ctx.rect(x, base - n * root.seg_step + 2, root.bar_w, n * root.seg_step - 2);
        else ctx.rect(x, base - n * root.seg_step + 2, root.bar_w, root.seg_h);
        ctx.fill();
    }

    // A dashed step line over the bars, with a dark halo so it reads on both shades.
    function dash_steps(ctx, ys) {
        const col_w = track.hour_col_w;
        for (const pass of [0, 1]) {
            const pad = pass === 0 ? 1 : 0;
            ctx.fillStyle = String(root.shades[pass === 0 ? 0 : 3]);
            ctx.beginPath();
            for (let i = 0; i < ys.length; i++) {
                const x0 = track.left_of(i);
                for (let dx = 0; dx < col_w; dx += 8) ctx.rect(x0 + dx - pad, ys[i] - pad, 4 + 2 * pad, 2 + 2 * pad);
                if (i + 1 < ys.length) {
                    const top = Math.min(ys[i], ys[i + 1]);
                    const span = Math.abs(ys[i + 1] - ys[i]);
                    for (let dy = 0; dy <= span; dy += 6) ctx.rect(x0 + col_w - 1 - pad, top + dy - pad, 2 + 2 * pad, 3 + 2 * pad);
                }
            }
            ctx.fill();
        }
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const values = hrs.map(track.value_of);
        const range = root.scale_range(hrs);
        const base = root.base_y(h);
        const lit = values.map(v => root.lit_of(v, range, h));
        const bar_x = i => Math.round(track.x_of(i) - root.bar_w / 2);

        // Day boundaries: a dotted rule and the day's name.
        ctx.fillStyle = String(root.shades[1]);
        ctx.beginPath();
        for (const b of track.day_boundaries) {
            const x = Math.round(track.left_of(b.index));
            for (let y = 12; y < base; y += 4) ctx.rect(x, y, 2, 2);
        }
        ctx.fill();
        ctx.fillStyle = String(root.shades[2]);
        ctx.font = "8px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (const b of track.day_boundaries) ctx.fillText(b.label, track.left_of(b.index) + 5, 8);

        for (let i = 0; i < hrs.length; i++) root.bar_rects(ctx, bar_x(i), base, lit[i], i === root.hour_cursor);

        const secondary = root.secondary_of(hrs);
        const secondary_lit = secondary ? secondary.map(v => root.lit_of(v, range, h)) : lit;
        if (secondary) root.dash_steps(ctx, secondary_lit.map(n => root.level_y(n, h) + 2));

        ctx.font = "8px \"" + Style.font_family + "\"";
        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) {
            if (i === root.hour_cursor) continue;
            ctx.fillStyle = String(root.shades[2]);
            ctx.fillText(root.value_text(values[i]), Math.round(track.x_of(i)), Math.max(18, root.level_y(Math.max(lit[i], secondary_lit[i]), h) - 2));
        }

        if (root.sub === 1) {
            const row_y = base + 4;
            for (let i = 0; i < hrs.length; i++) {
                const fill = Math.min(1, hrs[i].precip / root.precip_full_scale);
                const sel = i === root.hour_cursor;
                ctx.fillStyle = String(root.shades[1]);
                ctx.fillRect(bar_x(i), row_y, root.bar_w, 4);
                if (hrs[i].precip > 0) {
                    ctx.fillStyle = String(root.shades[sel ? 3 : 2]);
                    ctx.fillRect(bar_x(i), row_y, Math.max(2, Math.round(fill * root.bar_w / 2) * 2), 4);
                }
                ctx.fillStyle = String(root.shades[sel ? 3 : 2]);
                ctx.fillText(hrs[i].precip.toFixed(hrs[i].precip < 1 ? 2 : 1), Math.round(track.x_of(i)), row_y + 14);
            }
        }

        // The tuner dial: a baseline with a tick per hour, longer every third and at each day.
        const dial_y = h - root.dial_h;
        ctx.fillStyle = String(root.shades[2]);
        ctx.fillRect(0, dial_y, w, 2);
        ctx.beginPath();
        for (let i = 0; i < hrs.length; i++) {
            const x = Math.round(track.x_of(i)) - 1;
            ctx.rect(x, dial_y + 2, 2, i % 3 === 0 ? 8 : 4);
        }
        ctx.fill();
        ctx.fillStyle = String(root.shades[3]);
        ctx.beginPath();
        for (const b of track.day_boundaries) ctx.rect(Math.round(track.left_of(b.index)), dial_y + 2, 2, 12);
        ctx.fill();
    }

    onHour_cursorChanged: track.request_paint()

    readonly property string value_prefix: root.cursor_row ? "RADIO · " + WeatherState.format_hour(new Date(root.cursor_row.dt)).toUpperCase() + " · " : "RADIO · "
    readonly property string value_line: {
        const r = root.cursor_row;
        if (!r) return "";
        if (root.sub === 1) return r.pop + "%";
        if (root.sub === 2) return Math.round(r.wind_speed) + WeatherState.wind_unit().toUpperCase();
        if (root.sub === 3) return "UV " + r.uv_index.toFixed(1);
        if (root.sub === 4) return r.humidity + "%";
        return "";
    }
    readonly property string detail_line: {
        const r = root.cursor_row;
        if (!r) return "";
        const parts = [];
        if (root.sub === 0) parts.push("FEELS " + Math.round(r.feels));
        else if (root.sub === 2) parts.push("GUST " + Math.round(r.wind_gusts), WeatherState.compass_label(r.wind_dir));
        else parts.push(Math.round(r.temp) + WeatherState.unit_symbol());
        parts.push(r.pop + "% RAIN", r.precip.toFixed(2) + " " + root.precip_unit, r.cond.toUpperCase());
        return parts.join(" · ");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Item {
            Layout.fillWidth: true
            implicitHeight: 64

            PixelBox {
                anchors.fill: parent
                fill: root.shades[0]
                rings: [root.shades[2], root.shades[0], root.shades[3]]
            }

            PixelSprite {
                id: readout_icon
                visible: root.cursor_valid
                x: 12
                y: Math.round((parent.height - height) / 2)
                pixel: 2
                rows: root.cursor_valid ? PixelArt.sprite(root.cursor_row.code, root.cursor_row.is_day) : []
            }

            ColumnLayout {
                anchors.left: readout_icon.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 12
                spacing: 6

                Row {
                    Layout.fillWidth: true

                    Text {
                        text: root.value_prefix
                        color: root.shades[3]
                        font.family: Style.font_family
                        font.pixelSize: 16
                    }

                    PixelTemp {
                        visible: root.sub === 0 && root.cursor_valid
                        value: root.cursor_row ? root.cursor_row.temp : 0
                        unit: WeatherState.unit_symbol()
                        color: root.shades[3]
                        font_size: 16
                    }

                    Text {
                        text: root.value_line
                        color: root.shades[3]
                        font.family: Style.font_family
                        font.pixelSize: 16
                    }
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.detail_line
                    color: root.shades[2]
                    font.family: Style.font_family
                    font.pixelSize: 8
                }
            }
        }

        PixelBox {
            Layout.fillWidth: true
            Layout.fillHeight: true
            fill: root.shades[0]
            rings: [root.shades[2], root.shades[0]]

            Text {
                x: 10
                y: -2
                leftPadding: 4
                rightPadding: 4
                text: root.channel_names[root.sub]
                color: root.shades[0]
                font.family: Style.font_family
                font.pixelSize: 8

                Rectangle {
                    z: -1
                    anchors.fill: parent
                    color: root.shades[2]
                }
            }

            HourlyTrack {
                id: track
                anchors.fill: parent
                anchors.margins: 6
                anchors.topMargin: 10
                icon_row_h: 30
                label_row_h: 14
                hour_cursor: root.hour_cursor
                sub: root.sub
                on_select: i => root.on_select(i)
                scroll_x: root.scroll_x
                on_scroll: x => root.on_scroll(x)
                paint: root.paint
                caps_day_labels: true

                underlay: [
                    Rectangle {
                        visible: root.cursor_valid
                        x: track.left_of(root.hour_cursor)
                        width: track.hour_col_w
                        height: track.height
                        color: root.shades[1]
                    }
                ]

                // The needle sits on the cursor hour's dial tick, with a stepped cap.
                Item {
                    visible: root.cursor_valid
                    x: Math.round(track.x_of(root.hour_cursor)) - 4
                    width: 8
                    height: track.chart_h

                    Rectangle { y: 0; x: 0; width: 8; height: 2; color: root.shades[3] }
                    Rectangle { y: 2; x: 2; width: 4; height: 2; color: root.shades[3] }
                    Rectangle { x: 3; y: 4; width: 2; height: parent.height - 4; color: root.shades[3] }
                }

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

                        PixelSprite {
                            visible: root.sub !== 2
                            x: Math.round((parent.width - width) / 2)
                            y: Math.round((track.icon_row_h - height) / 2)
                            pixel: 2
                            colors: hour_col.selected ? root.shades : [root.shades[0], root.shades[1], root.shades[1], root.shades[2]]
                            rows: PixelArt.sprite(hour_col.modelData.code, hour_col.modelData.is_day)
                        }

                        Text {
                            visible: root.sub === 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Math.round((track.icon_row_h - height) / 2)
                            text: WeatherState.compass_label(hour_col.modelData.wind_dir)
                            color: hour_col.selected ? root.shades[3] : root.shades[2]
                            font.family: Style.font_family
                            font.pixelSize: 16
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: track.icon_row_h + 1
                            width: hour_label.implicitWidth + 6
                            height: hour_label.implicitHeight + 2
                            color: hour_col.selected ? root.shades[3] : "transparent"

                            Text {
                                id: hour_label
                                anchors.centerIn: parent
                                text: WeatherState.format_hour(new Date(hour_col.modelData.dt)).toUpperCase()
                                color: hour_col.selected ? root.shades[0] : root.shades[2]
                                font.family: Style.font_family
                                font.pixelSize: 8
                            }
                        }
                    }
                }
            }
        }
    }
}
