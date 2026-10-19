import QtQuick
import QtQuick.Layouts
import qs.core
import qs.ui.effects
import qs.theme
import qs.features.weather
import qs.features.weather.views.shared
import qs.styles.nes.widgets
import "../../../../styles/nes/widgets/Slimes.js" as Slimes

// The hours as a Dragon Quest field map: a stepped line in a command window with a king slime hopping on the cursor hour, the hour's stats in a message window above.
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
    readonly property var line_colors: [Style.pal.bright_yellow, Style.pal.bright_blue, Style.pal.cyan, Style.pal.warning, Style.pal.green]
    readonly property color line_color: root.line_colors[Math.min(root.sub, root.line_colors.length - 1)]
    readonly property color rule_color: Style.pal.fg_strong

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]
    readonly property bool cursor_valid: root.hour_cursor >= 0 && root.hour_cursor < WeatherState.hours.length

    // Heavy rain in the forecast's own unit, so amount bars read the same in mm and inches.
    readonly property real precip_full_scale: WeatherState.metric ? 5 : 0.2

    readonly property int sprite_pixel: 2
    readonly property int sprite_h: Slimes.KING_SLIME.length * root.sprite_pixel
    readonly property int top_pad: root.sprite_h + 14
    readonly property int line_w: 2

    BattlePalette {
        id: palette
    }

    function value_text(v) {
        if (root.sub === 3) return v.toFixed(1);
        return Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
    }

    function secondary_of(hrs) {
        return root.sub === 0 ? hrs.map(r => r.feels) : root.sub === 2 ? hrs.map(r => r.wind_gusts) : null;
    }

    function secondary_name() {
        return root.sub === 0 ? "FEELS" : root.sub === 2 ? "GUST" : "";
    }

    // The dashed line shares the scale, so gusts above the speeds stay on screen.
    function scale_range(hrs) {
        const values = hrs.map(track.value_of).concat(root.secondary_of(hrs) || []);
        if (root.sub === 1 || root.sub === 4) return { lo: 0, hi: 100 };
        if (root.sub === 3) return { lo: 0, hi: Math.max(12, Math.max(...values) + 1) };
        let lo = Math.min(...values);
        let hi = Math.max(...values);
        const pad = Math.max(2, (hi - lo) * 0.15);
        return { lo: lo - pad, hi: hi + pad };
    }

    function bottom_pad() {
        return root.sub === 1 ? Style.fs(-6) + 22 : 6;
    }

    // Pixel row of a value on the chart; whole pixels keep the stepped line crisp.
    function y_of(v, range, h) {
        const plot_h = h - root.top_pad - root.bottom_pad();
        return Math.round(root.top_pad + plot_h - ((v - range.lo) / (range.hi - range.lo || 1)) * plot_h);
    }

    function sprite_y() {
        const hrs = WeatherState.hours;
        if (!root.cursor_valid || hrs.length === 0) return 0;
        const range = root.scale_range(hrs);
        return root.y_of(track.value_of(hrs[root.hour_cursor]), range, track.chart_h) - root.sprite_h + 1;
    }

    function scroll_to_cursor() {
        track.scroll_to_cursor();
    }

    function request_scroll() {
        track.request_scroll();
    }

    // A step line: each hour holds its level across the column, joined to the next by a vertical riser.
    function stroke_steps(ctx, ys, dashed) {
        const col_w = track.hour_col_w;
        const lw = root.line_w;
        for (let i = 0; i < ys.length; i++) {
            const x0 = track.left_of(i);
            if (dashed) {
                for (let dx = 0; dx < col_w; dx += 8) ctx.fillRect(x0 + dx, ys[i] - 1, 4, lw);
            } else {
                ctx.fillRect(x0, ys[i] - 1, col_w, lw);
            }
            if (i + 1 < ys.length) {
                const top = Math.min(ys[i], ys[i + 1]);
                const span = Math.abs(ys[i + 1] - ys[i]);
                const rx = x0 + col_w - 1;
                if (dashed) {
                    for (let dy = 0; dy <= span; dy += 6) ctx.fillRect(rx, top + dy, lw, Math.min(3, span - dy + 1));
                } else {
                    ctx.fillRect(rx, top - 1, lw, span + lw);
                }
            }
        }
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const values = hrs.map(track.value_of);
        const range = root.scale_range(hrs);
        const bottom_pad = root.bottom_pad();
        const floor_y = h - bottom_pad;
        const ys = values.map(v => root.y_of(v, range, h));

        // Dotted quarter rules.
        ctx.fillStyle = root.rule_color;
        ctx.globalAlpha = 0.18;
        const plot_h = h - root.top_pad - bottom_pad;
        for (let q = 0; q <= 4; q++) {
            const y = Math.round(root.top_pad + plot_h * q / 4);
            for (let x = 0; x < w; x += 8) ctx.fillRect(x, y, 2, 1);
        }
        ctx.globalAlpha = 0.45;
        for (const b of track.day_boundaries) {
            const x = Math.round(track.left_of(b.index));
            for (let y = 0; y < h; y += 6) ctx.fillRect(x, y, 1, 3);
        }
        ctx.globalAlpha = 1;
        ctx.fillStyle = Style.text_muted;
        ctx.font = Style.fs(-6) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (const b of track.day_boundaries) ctx.fillText(b.label, track.left_of(b.index) + 4, 10);

        if (root.sub === 1) {
            ctx.fillStyle = Style.pal.blue;
            ctx.globalAlpha = 0.2;
            for (let i = 0; i < hrs.length; i++) ctx.fillRect(track.left_of(i), ys[i], track.hour_col_w, floor_y - ys[i]);
            ctx.globalAlpha = 1;
            for (let i = 0; i < hrs.length; i++) {
                if (hrs[i].precip <= 0) continue;
                const bar_h = Math.max(2, Math.round(Math.min(1, hrs[i].precip / root.precip_full_scale) * 14));
                ctx.fillStyle = Style.pal.bright_blue;
                ctx.fillRect(Math.round(track.x_of(i)) - 6, floor_y + 2, 12, bar_h);
                ctx.fillStyle = Style.pal.fg_strong;
                ctx.font = Style.fs(-6) + "px \"" + Style.font_family + "\"";
                ctx.textAlign = "center";
                ctx.fillText(hrs[i].precip.toFixed(hrs[i].precip < 1 ? 2 : 1), track.x_of(i), h - 2);
            }
        }

        const secondary = root.secondary_of(hrs);
        const secondary_ys = secondary ? secondary.map(v => root.y_of(v, range, h)) : ys;
        if (secondary) {
            ctx.fillStyle = Style.pal.fg_strong;
            ctx.globalAlpha = 0.7;
            root.stroke_steps(ctx, secondary_ys, true);
            ctx.globalAlpha = 1;
        }

        ctx.fillStyle = root.line_color;
        root.stroke_steps(ctx, ys, false);

        ctx.fillStyle = Style.pal.fg_strong;
        ctx.font = Style.fs(-6) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) {
            if (i === root.hour_cursor) continue;
            ctx.fillText(root.value_text(values[i]), track.x_of(i), Math.max(20, Math.min(ys[i], secondary_ys[i]) - 6));
        }
    }

    onHour_cursorChanged: track.request_paint()

    readonly property string headline: {
        const r = root.cursor_row;
        if (!r) return "";
        return WeatherState.format_hour(new Date(r.dt)).toUpperCase();
    }

    readonly property string detail: {
        const r = root.cursor_row;
        if (!r) return "";
        const parts = [Math.round(r.temp) + "°" + WeatherState.unit_symbol(), r.pop + "% pop", r.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in"), r.cond];
        return parts.join(" · ");
    }

    readonly property string secondary_text: {
        const r = root.cursor_row;
        if (!r || root.secondary_name() === "") return "";
        return root.secondary_name() + " " + Math.round(root.sub === 0 ? r.feels : r.wind_gusts);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        DqWindow {
            Layout.fillWidth: true
            implicitHeight: message.implicitHeight + 24

            ColumnLayout {
                id: message
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: Style.row_cursor
                        color: Style.caret_color
                        visible: root.cursor_valid && Style.caret_phase
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                    }

                    Text {
                        text: root.headline
                        color: Style.pal.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-4)
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: root.secondary_text !== ""
                        text: "- " + root.secondary_text
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                    }

                    Text {
                        visible: !!root.cursor_row
                        text: root.cursor_row ? root.value_text(track.value_of(root.cursor_row)) : ""
                        color: root.line_color
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-4)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.detail
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                }
            }
        }

        DqWindow {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: root.channel_names[root.sub]

            HourlyTrack {
                id: track
                anchors.fill: parent
                anchors.margins: 8
                icon_row_h: 32
                label_row_h: 16
                hour_cursor: root.hour_cursor
                sub: root.sub
                on_select: i => root.on_select(i)
                scroll_x: root.scroll_x
                on_scroll: x => root.on_scroll(x)
                paint: root.paint
                caps_day_labels: true
                arrow_color: root.line_color
                label_color: Style.text_muted
                label_color_selected: Style.pal.fg_strong
                label_font_family: Style.font_family
                label_px: Style.fs(-6)

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

                        Image {
                            visible: root.sub !== 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: track.icon_row_h
                            height: track.icon_row_h
                            sourceSize.width: 16
                            sourceSize.height: 16
                            source: WeatherState.icon_source(hour_col.modelData.code, hour_col.modelData.is_day)
                            smooth: false
                            opacity: hour_col.selected ? 1 : 0.6
                        }

                        Text {
                            visible: root.sub === 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.top
                            anchors.verticalCenterOffset: track.icon_row_h / 2
                            text: "▲"
                            rotation: hour_col.modelData.wind_dir
                            color: root.line_color
                            font.pixelSize: Style.font_size
                        }

                        Text {
                            id: hour_label
                            anchors.top: parent.top
                            anchors.topMargin: track.icon_row_h + 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: WeatherState.format_hour(new Date(hour_col.modelData.dt)).toUpperCase()
                            color: hour_col.selected ? Style.pal.fg_strong : Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-6)

                            Text {
                                visible: hour_col.selected && Style.caret_phase
                                anchors.right: parent.left
                                anchors.rightMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                text: Style.row_cursor
                                color: Style.caret_color
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-6)
                            }
                        }
                    }
                }

                Rectangle {
                    visible: root.cursor_valid
                    x: track.left_of(root.hour_cursor)
                    width: track.hour_col_w
                    height: track.chart_h
                    color: Style.pal.fg_strong
                    opacity: 0.07
                }

                PixelSprite {
                    id: king
                    visible: root.cursor_valid && WeatherState.hours.length > 0
                    pixel: root.sprite_pixel
                    colors: palette.colors
                    rows: Slimes.KING_SLIME
                    x: Math.round(track.x_of(root.hour_cursor) - width / 2)
                    y: root.sprite_y()
                    // The hop is a transform, so the slide Behavior on y does not animate it.
                    transform: Translate { y: king.hopped ? -root.sprite_pixel : 0 }

                    property bool hopped: false
                    property bool settled: false

                    Behavior on x {
                        enabled: king.settled
                        NumberAnimation {
                            duration: 140
                        }
                    }

                    Behavior on y {
                        enabled: king.settled
                        NumberAnimation {
                            duration: 140
                        }
                    }

                    Timer {
                        running: root.cursor_valid && king.visible && PowerSource.on_ac
                        interval: 500
                        repeat: true
                        onTriggered: king.hopped = !king.hopped
                        onRunningChanged: if (!running) king.hopped = false
                    }

                    Component.onCompleted: Qt.callLater(() => { king.settled = true; })
                }
            }
        }
    }
}
