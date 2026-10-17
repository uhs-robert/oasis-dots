import QtQuick
import QtQuick.Layouts
import qs.ui.frames
import qs.theme
import qs.services
import qs.styles.reticle.widgets

// The targeting computer's range chart: the hours as a trace on a flat grid with a range ruler, the cursor hour held in closing lock brackets.
// A flat plot rather than a trench in perspective, because receding columns would shrink the labels the scroll has to keep readable.
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

    readonly property color vec: Style.text_primary
    readonly property color vec_dim: Style.text_muted
    readonly property color lock: Style.selection_brackets.a > 0 ? Style.selection_brackets : Theme.theme_label
    readonly property int top_pad: 32
    readonly property int legend_h: Math.round(Style.fs(-3) + 8)
    readonly property real amount_px: Style.fs(-3)
    // Heavy rain in the forecast's own unit, so amount bars read the same in mm and inches.
    readonly property real precip_full_scale: WeatherState.metric ? 5 : 0.2

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]
    readonly property bool has_cursor: !!root.cursor_row
    // Bound once per change of data or sub, not per y_of call, since paint() maps every point through it.
    readonly property var value_range: root.scale_range(WeatherState.hours)

    function scroll_to_cursor() {
        track.scroll_to_cursor();
    }

    function request_scroll() {
        track.request_scroll();
    }

    function value_text(v) {
        if (root.sub === 3) return v.toFixed(1);
        return Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
    }

    function unit_text() {
        return ["°" + WeatherState.unit_symbol(), "%", WeatherState.wind_unit(), "INDEX", "% RH"][root.sub];
    }

    function secondary_name() {
        return root.sub === 0 ? "FEELS" : root.sub === 2 ? "GUSTS" : "";
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

    function plot_bottom_pad() {
        return root.sub === 1 ? root.amount_px + 8 : 6;
    }

    function y_of(v, h) {
        const plot_h = h - root.top_pad - root.plot_bottom_pad();
        const range = root.value_range;
        return root.top_pad + plot_h - ((v - range.lo) / (range.hi - range.lo || 1)) * plot_h;
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const values = hrs.map(track.value_of);
        const bottom_pad = root.plot_bottom_pad();
        const plot_h = h - root.top_pad - bottom_pad;
        const x_of = track.x_of;
        const y_of = v => root.y_of(v, h);

        // Range grid: hour columns, a heavier line every six hours, four horizontal divisions.
        ctx.lineWidth = 1;
        ctx.strokeStyle = root.vec;
        for (let i = 0; i <= hrs.length; i++) {
            const x = Math.round(i * track.hour_col_w) + 0.5;
            ctx.globalAlpha = i < hrs.length && i % 6 === 0 ? 0.2 : 0.06;
            ctx.beginPath();
            ctx.moveTo(x, root.top_pad - 6);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        for (let d = 0; d <= 4; d++) {
            const y = Math.round(root.top_pad + plot_h * d / 4) + 0.5;
            ctx.globalAlpha = d === 2 ? 0.24 : 0.09;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(w, y);
            ctx.stroke();
        }

        // Range ruler along the top: a tick per hour, a long one and a "+N" range figure every six.
        ctx.globalAlpha = 0.7;
        for (let i = 0; i <= hrs.length * 2; i++) {
            const x = Math.round(i * track.hour_col_w / 2) + 0.5;
            const major = i % 12 === 0;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, major ? 8 : i % 2 === 0 ? 5 : 3);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;
        ctx.fillStyle = root.vec_dim;
        ctx.font = Style.fs(-5) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (let i = 0; i < hrs.length; i += 6) ctx.fillText("+" + i, track.left_of(i) + 3, 18);

        ctx.strokeStyle = root.lock;
        ctx.globalAlpha = 0.55;
        for (const b of track.day_boundaries) {
            const x = Math.round(track.left_of(b.index)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;
        ctx.fillStyle = root.vec;
        ctx.font = "bold " + Style.fs(-4) + "px \"" + Style.font_family + "\"";
        for (const b of track.day_boundaries) ctx.fillText(b.label, track.left_of(b.index) + 3, 29);

        if (root.sub === 1) {
            ctx.fillStyle = root.vec;
            for (let i = 0; i < hrs.length; i++) {
                if (hrs[i].precip <= 0) continue;
                const bar_h = Math.max(1, Math.min(1, hrs[i].precip / root.precip_full_scale) * 16);
                ctx.globalAlpha = 0.5;
                ctx.fillRect(x_of(i) - 7, h - bottom_pad - bar_h, 14, bar_h);
            }
            ctx.globalAlpha = 0.1;
            ctx.beginPath();
            ctx.moveTo(x_of(0), h - bottom_pad);
            for (let i = 0; i < hrs.length; i++) ctx.lineTo(x_of(i), y_of(hrs[i].pop));
            ctx.lineTo(x_of(hrs.length - 1), h - bottom_pad);
            ctx.closePath();
            ctx.fill();
            ctx.globalAlpha = 1;
        }

        // Dashed second trace: feels-like for temp, gusts for wind.
        const secondary = root.secondary_of(hrs);
        if (secondary) {
            ctx.setLineDash([4, 3]);
            ctx.strokeStyle = root.vec_dim;
            ctx.lineWidth = 1.2;
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                if (i === 0) ctx.moveTo(x_of(i), y_of(secondary[i])); else ctx.lineTo(x_of(i), y_of(secondary[i]));
            }
            ctx.stroke();
            ctx.setLineDash([]);
        }

        ctx.strokeStyle = root.vec;
        ctx.lineJoin = "round";
        ctx.lineWidth = 1.6;
        ctx.beginPath();
        for (let i = 0; i < hrs.length; i++) {
            if (i === 0) ctx.moveTo(x_of(i), y_of(values[i])); else ctx.lineTo(x_of(i), y_of(values[i]));
        }
        ctx.stroke();

        ctx.fillStyle = root.vec;
        for (let i = 0; i < hrs.length; i++) ctx.fillRect(x_of(i) - 1.5, y_of(values[i]) - 1.5, 3, 3);

        ctx.fillStyle = Style.text_strong;
        ctx.font = "bold " + Style.fs(-3) + "px \"" + Style.number_font + "\"";
        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) ctx.fillText(root.value_text(values[i]), x_of(i), Math.max(root.top_pad + 6, y_of(values[i]) - 9));

        if (root.sub === 1) {
            ctx.fillStyle = root.vec_dim;
            ctx.font = root.amount_px + "px \"" + Style.number_font + "\"";
            for (let i = 0; i < hrs.length; i++) ctx.fillText(hrs[i].precip.toFixed(hrs[i].precip < 1 ? 2 : 1), x_of(i), h - 3);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.has_cursor ? "RANGE " + String(root.hour_cursor).padStart(2, "0") + " · " + root.value_text(track.value_of(root.cursor_row)) : "RANGE --"
                color: root.lock
                font.family: Style.number_font
                font.pixelSize: Style.fs(2)
                font.bold: true
                font.letterSpacing: 1
            }

            Text {
                text: root.channel_names[root.sub] + " " + root.unit_text()
                color: root.vec
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.bold: true
                font.letterSpacing: 1.5
            }

            Text {
                visible: root.secondary_name() !== ""
                text: "- - " + root.secondary_name()
                color: root.vec_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.bold: true
                font.letterSpacing: 1.5
            }

            Text {
                visible: root.sub === 1
                text: "▮ " + (WeatherState.metric ? "MM" : "IN")
                color: root.vec_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.bold: true
                font.letterSpacing: 1.5
            }
        }

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: {
                const r = root.cursor_row;
                if (!r) return "";
                return [WeatherState.format_hour(new Date(r.dt)), Math.round(r.temp) + "°" + WeatherState.unit_symbol(), r.pop + "% pop", r.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in"), r.cond].join(" · ");
            }
            color: root.vec_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 3
            Layout.bottomMargin: 4

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(root.vec, 0.22)
            }

            CornerBrackets {
                anchors.fill: parent
                color: root.vec
                inset: 0
                arm: 12
                thickness: 1.5
                all_corners: true
            }

            HourlyTrack {
                id: track
                anchors.fill: parent
                anchors.margins: 3
                icon_row_h: 28
                hour_cursor: root.hour_cursor
                sub: root.sub
                on_select: i => root.on_select(i)
                scroll_x: root.scroll_x
                on_scroll: x => root.on_scroll(x)
                paint: root.paint
                caps_day_labels: true
                // The shared cell's plain icons would ignore the HUD's one-colour weather_icon_tint.
                cell: Component {
                    Item {
                        id: hour_cell
                        required property var modelData
                        required property int index
                        readonly property bool selected: hour_cell.index === root.hour_cursor

                        x: track.left_of(hour_cell.index)
                        y: track.chart_h + 4
                        width: track.hour_col_w
                        height: track.icon_row_h + track.label_row_h

                        WeatherIcon {
                            visible: root.sub !== 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            size: track.icon_row_h - 2
                            code: hour_cell.modelData.code
                            is_day: hour_cell.modelData.is_day
                        }

                        Text {
                            visible: root.sub === 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: (track.icon_row_h - height) / 2
                            text: "▲"
                            rotation: hour_cell.modelData.wind_dir
                            color: root.vec
                            font.pixelSize: Style.font_size
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: track.icon_row_h
                            text: WeatherState.format_hour(new Date(hour_cell.modelData.dt))
                            color: hour_cell.selected ? root.lock : root.vec_dim
                            font.family: Style.number_font
                            font.pixelSize: Style.fs(-3)
                            font.bold: hour_cell.selected
                        }
                    }
                }

                Rectangle {
                    visible: root.has_cursor
                    x: track.left_of(root.hour_cursor)
                    width: track.hour_col_w
                    height: track.chart_h
                    color: Style.selection_bg
                }

                Rectangle {
                    visible: root.has_cursor
                    x: track.x_of(root.hour_cursor) - 0.5
                    y: root.top_pad - 6
                    width: 1
                    height: track.chart_h - root.top_pad + 6
                    color: root.lock
                    opacity: 0.45
                }

                Reticle {
                    visible: root.has_cursor
                    width: 20
                    height: 20
                    x: track.x_of(root.hour_cursor) - 10
                    y: (root.cursor_row ? root.y_of(track.value_of(root.cursor_row), track.chart_h) : 0) - 10
                    color: root.lock
                    center_color: root.lock
                }

                // The brackets close in on the new hour whenever the cursor moves.
                Item {
                    id: lock_box
                    property real gap: 0
                    visible: root.has_cursor
                    x: track.left_of(root.hour_cursor)
                    width: track.hour_col_w
                    height: track.chart_h + 4 + track.icon_row_h + track.label_row_h

                    CornerBrackets {
                        anchors.fill: parent
                        color: root.lock
                        inset: lock_box.gap
                        arm: 9
                        thickness: 1.5
                        all_corners: true
                    }

                    NumberAnimation {
                        id: close_in
                        target: lock_box
                        property: "gap"
                        from: -9
                        to: 0
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    onHour_cursorChanged: close_in.restart()
}
