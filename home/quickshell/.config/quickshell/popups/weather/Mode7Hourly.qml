import QtQuick
import QtQuick.Layouts
import qs.ui.effects
import qs.styles.snes.widgets as Snes
import qs.theme
import qs.services

// The hours as gauge pillars standing on the Mode 7 floor, a kart parked at the cursor hour, the hour's stats in an RPG window above.
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
    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]
    readonly property bool cursor_valid: root.hour_cursor >= 0 && root.hour_cursor < WeatherState.hours.length
    readonly property bool scene_live: root.visible && Popups.open_name === "weather"

    readonly property color sub_color: root.color_of(root.cursor_row)
    // Heavy rain in the forecast's own unit, so the amount bar reads the same in mm and inches.
    readonly property real precip_full_scale: WeatherState.metric ? 5 : 0.2

    readonly property int pillar_w: 16
    readonly property int cap_h: 6
    // Room over the tallest pillar for its value and the cursor hand, under the day label.
    readonly property int top_pad: 46
    readonly property int foot_h: 12
    readonly property int amount_h: root.sub === 1 ? 11 : 0
    readonly property real horizon_frac: 0.4

    // Stepped, not eased: SNES menu cursors jump whole pixels.
    property int bob: 0

    SequentialAnimation {
        running: root.scene_live && root.cursor_valid
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.bob = 0
        PropertyAction { target: root; property: "bob"; value: 0 }
        PauseAnimation { duration: 180 }
        PropertyAction { target: root; property: "bob"; value: 2 }
        PauseAnimation { duration: 180 }
        PropertyAction { target: root; property: "bob"; value: 3 }
        PauseAnimation { duration: 180 }
        PropertyAction { target: root; property: "bob"; value: 2 }
        PauseAnimation { duration: 180 }
    }

    FontMetrics {
        id: big_metrics
        font.family: Style.font_family
        font.pixelSize: Style.font_size
    }

    function color_of(row) {
        if (root.sub === 3) return row ? WeatherState.uv_color(row.uv_index) : Style.pal.green;
        return [Style.pal.primary_strong, Style.pal.info, Style.pal.cyan, Style.pal.green, Style.pal.bright_cyan][root.sub];
    }

    function value_text(v) {
        if (root.sub === 3) return v.toFixed(1);
        return Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
    }

    // The largest pixel size the label fits a column in; 8px is Silkscreen's other grid step.
    function label_px(text) {
        return big_metrics.advanceWidth(text) <= track.hour_col_w - 4 ? Style.font_size : Style.fs(-8);
    }

    function secondary_of(hrs) {
        return root.sub === 0 ? hrs.map(r => r.feels) : root.sub === 2 ? hrs.map(r => r.wind_gusts) : null;
    }

    function secondary_name() {
        return root.sub === 0 ? "FEELS" : root.sub === 2 ? "GUST" : "";
    }

    // Pillars rise from the scale's low: zero, except temperature, whose low floats with the data. Feels-like and gusts share the scale.
    function scale_range(hrs) {
        if (hrs.length === 0) return { lo: 0, hi: 1 };
        const values = hrs.map(track.value_of).concat(root.secondary_of(hrs) || []);
        if (root.sub === 1 || root.sub === 4) return { lo: 0, hi: 100 };
        if (root.sub === 3) return { lo: 0, hi: Math.max(12, Math.max(...values) + 1) };
        const hi = Math.max(...values);
        if (root.sub === 2) return { lo: 0, hi: Math.max(10, hi * 1.1) };
        const lo = Math.min(...values);
        const pad = Math.max(2, (hi - lo) * 0.15);
        return { lo: lo - pad, hi: hi + pad };
    }

    function base_y(h) {
        return h - root.foot_h - root.amount_h;
    }

    function y_of(v, range, h) {
        const frac = Math.max(0, Math.min(1, (v - range.lo) / (range.hi - range.lo || 1)));
        const base = root.base_y(h);
        return Math.round(base - Math.max(0.03, frac) * (base - root.top_pad));
    }

    function top_of_cursor() {
        const hrs = WeatherState.hours;
        if (!root.cursor_valid || hrs.length === 0) return root.top_pad;
        return root.y_of(track.value_of(hrs[root.hour_cursor]), root.scale_range(hrs), track.chart_h);
    }

    function scroll_to_cursor() {
        track.scroll_to_cursor();
    }

    function request_scroll() {
        track.request_scroll();
    }

    function shadowed_text(ctx, text, x, y, color) {
        ctx.fillStyle = String(Style.text_shadow);
        ctx.fillText(text, x + 1, y + 1);
        ctx.fillStyle = String(color);
        ctx.fillText(text, x, y);
    }

    function ellipse(ctx, cx, cy, rx, ry) {
        ctx.save();
        ctx.translate(cx, cy);
        ctx.scale(1, ry / rx);
        ctx.beginPath();
        ctx.arc(0, 0, rx, 0, 2 * Math.PI);
        ctx.restore();
    }

    function pillar(ctx, cx, y_top, base, color, selected) {
        const pw = root.pillar_w;
        const x0 = cx - pw / 2;
        const shade = Qt.tint(color, Qt.alpha(Style.pal.fg_strong, 0.4));

        ctx.globalAlpha = 0.5;
        ctx.fillStyle = String(Style.pal.bg_shadow);
        root.ellipse(ctx, cx, base + 1, pw * 0.75, root.cap_h);
        ctx.fill();
        ctx.globalAlpha = 1;

        const body = ctx.createLinearGradient(0, y_top, 0, base);
        body.addColorStop(0, String(shade));
        body.addColorStop(1, String(color));
        ctx.fillStyle = body;
        ctx.fillRect(x0, y_top, pw, base - y_top);
        ctx.globalAlpha = 0.35;
        ctx.fillStyle = String(Style.pal.bg_crust);
        for (let y = base - 8; y > y_top; y -= 8) ctx.fillRect(x0, y, pw, 1);
        ctx.globalAlpha = 0.28;
        ctx.fillStyle = String(Style.pal.fg_strong);
        ctx.fillRect(x0 + 2, y_top, 3, base - y_top);
        ctx.globalAlpha = 0.45;
        ctx.fillStyle = String(Style.pal.bg_shadow);
        ctx.fillRect(x0 + Math.round(pw * 0.62), y_top, pw - Math.round(pw * 0.62), base - y_top);
        ctx.globalAlpha = 1;

        ctx.fillStyle = String(Style.pal.bg_shadow);
        root.ellipse(ctx, cx, base, pw / 2, root.cap_h / 2);
        ctx.fill();
        root.ellipse(ctx, cx, y_top, pw / 2, root.cap_h / 2);
        ctx.fillStyle = String(selected ? Style.pal.fg_strong : Style.pal.primary_light);
        ctx.fill();
        ctx.strokeStyle = String(selected ? Style.pal.secondary : Style.pal.fg_muted);
        ctx.lineWidth = 1;
        ctx.stroke();
    }

    function paint(ctx, w, h) {
        ctx.reset();
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const values = hrs.map(track.value_of);
        const range = root.scale_range(hrs);
        const base = root.base_y(h);
        const family = "\"" + Style.font_family + "\"";

        ctx.fillStyle = String(Style.pal.fg_strong);
        ctx.globalAlpha = 0.3;
        for (const b of track.day_boundaries) {
            const x = Math.round(track.left_of(b.index));
            for (let y = 0; y < h; y += 6) ctx.fillRect(x, y, 1, 3);
        }
        ctx.globalAlpha = 1;
        ctx.font = Style.fs(-8) + "px " + family;
        ctx.textAlign = "left";
        for (const b of track.day_boundaries) root.shadowed_text(ctx, b.label, track.left_of(b.index) + 4, 10, Style.pal.primary_light);

        for (let i = 0; i < hrs.length; i++) {
            const color = root.sub === 3 ? WeatherState.uv_color(hrs[i].uv_index) : root.sub_color_flat;
            root.pillar(ctx, Math.round(track.x_of(i)), root.y_of(values[i], range, h), base, color, i === root.hour_cursor);
        }

        const secondary = root.secondary_of(hrs);
        if (secondary) {
            ctx.fillStyle = String(Style.pal.fg_strong);
            for (let i = 0; i < hrs.length; i++) {
                const y = root.y_of(secondary[i], range, h);
                const x0 = Math.round(track.left_of(i)) + 4;
                for (let dx = 0; dx < track.hour_col_w - 8; dx += 6) ctx.fillRect(x0 + dx, y - 1, 3, 2);
            }
        }

        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) {
            const text = root.value_text(values[i]);
            const px = root.label_px(text);
            ctx.font = px + "px " + family;
            const y_top = root.y_of(values[i], range, h);
            const above = secondary ? Math.min(y_top, root.y_of(secondary[i], range, h)) : y_top;
            root.shadowed_text(ctx, text, track.x_of(i), above - root.cap_h / 2 - 4, i === root.hour_cursor ? Style.pal.fg_strong : Style.pal.fg);
        }

        if (root.sub === 1) {
            ctx.font = Style.fs(-8) + "px " + family;
            for (let i = 0; i < hrs.length; i++) {
                const amount = hrs[i].precip;
                const bar_w = Math.round(Math.min(1, amount / root.precip_full_scale) * (track.hour_col_w - 12));
                ctx.fillStyle = String(Style.pal.bg_shadow);
                ctx.fillRect(Math.round(track.left_of(i)) + 6, h - 9, track.hour_col_w - 12, 2);
                ctx.fillStyle = String(Style.pal.bright_blue);
                ctx.fillRect(Math.round(track.left_of(i)) + 6, h - 9, bar_w, 2);
                root.shadowed_text(ctx, amount.toFixed(amount < 1 ? 2 : 1), track.x_of(i), h - 1, Style.pal.fg_strong);
            }
        }
    }

    readonly property color sub_color_flat: root.color_of(null)

    onHour_cursorChanged: {
        track.request_paint();
        if (root.scene_live && floor_loader.item) floor_loader.item.run();
    }

    onScene_liveChanged: {
        if (!floor_loader.item) return;
        if (root.scene_live) floor_loader.item.run();
        else floor_loader.item.stop();
    }

    readonly property string headline: {
        const r = root.cursor_row;
        return r ? WeatherState.format_hour(new Date(r.dt)).toUpperCase() : "";
    }

    readonly property string detail: {
        const r = root.cursor_row;
        if (!r) return "";
        const parts = [Math.round(r.temp) + "°" + WeatherState.unit_symbol(), r.pop + "% pop", r.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in")];
        if (root.secondary_name() !== "") parts.push(root.secondary_name() + " " + Math.round(root.sub === 0 ? r.feels : r.wind_gusts));
        return parts.join(" · ").toUpperCase();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Snes.SnesWindow {
            id: readout_window
            Layout.fillWidth: true
            implicitHeight: readout.implicitHeight + 22

            ColumnLayout {
                id: readout
                anchors.left: readout_window.panel.left
                anchors.right: readout_window.panel.right
                anchors.verticalCenter: readout_window.panel.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: root.headline
                        color: Style.pal.secondary
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: root.cursor_row ? root.cursor_row.cond.toUpperCase() : ""
                        color: Style.pal.primary_light
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-8)
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    Text {
                        text: root.cursor_row ? root.channel_names[root.sub] + " " + root.value_text(track.value_of(root.cursor_row)) : ""
                        color: Style.pal.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.detail
                    color: Style.pal.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-8)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }
            }
        }

        Snes.SnesWindow {
            id: scene_window
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                id: stage
                anchors.fill: scene_window.panel
                anchors.margins: 6

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_strong, 0.55)) }
                        GradientStop { position: 1; color: Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_light, 0.3)) }
                    }
                }

                Rectangle {
                    y: Math.round(track.chart_h * root.horizon_frac)
                    width: parent.width
                    height: track.chart_h - y + 4
                    color: Qt.tint(Style.pal.bg_crust, Qt.alpha(Style.pal.primary_strong, 0.25))
                }

                Loader {
                    id: floor_loader
                    y: Math.round(track.chart_h * root.horizon_frac)
                    width: parent.width
                    height: track.chart_h - y + 4
                    sourceComponent: Mode7Floor {}
                    onLoaded: if (root.scene_live) floor_loader.item.run()
                }

                Rectangle {
                    y: track.chart_h + 4
                    width: parent.width
                    height: parent.height - y
                    color: Qt.alpha(Style.pal.bg_crust, 0.7)
                }

                HourlyTrack {
                    id: track
                    anchors.fill: parent
                    icon_row_h: 34
                    label_row_h: 14
                    hour_cursor: root.hour_cursor
                    sub: root.sub
                    on_select: i => root.on_select(i)
                    scroll_x: root.scroll_x
                    on_scroll: x => root.on_scroll(x)
                    paint: root.paint
                    caps_day_labels: true
                    arrow_color: root.sub_color

                    cell: Component {
                        Item {
                            id: hour_col
                            required property var modelData
                            required property int index
                            readonly property bool selected: hour_col.index === root.hour_cursor
                            readonly property var crop: WeatherState.icon_crop(hour_col.modelData.code, hour_col.modelData.is_day)
                            readonly property real unit: 16 / hour_col.crop[2]

                            x: track.left_of(hour_col.index)
                            y: track.chart_h + 4
                            width: track.hour_col_w
                            height: track.icon_row_h + track.label_row_h

                            Rectangle {
                                visible: hour_col.selected
                                anchors.fill: parent
                                anchors.leftMargin: 3
                                anchors.rightMargin: 3
                                radius: 3
                                color: Qt.alpha(Style.pal.secondary, 0.22)
                                border.width: 1
                                border.color: Style.pal.secondary
                            }

                            // The icon's art crop is rasterised at 16px and blown up unsmoothed, so it reads as a 16x16 sprite.
                            Item {
                                visible: root.sub !== 2
                                x: Math.round((parent.width - width) / 2)
                                y: 2
                                width: 32
                                height: 32
                                clip: true

                                Image {
                                    x: -Math.round(hour_col.crop[0] * hour_col.unit) * 2
                                    y: -Math.round(hour_col.crop[1] * hour_col.unit) * 2
                                    width: Math.round(128 * hour_col.unit) * 2
                                    height: width
                                    sourceSize.width: Math.round(128 * hour_col.unit)
                                    sourceSize.height: Math.round(128 * hour_col.unit)
                                    source: WeatherState.icon_source(hour_col.modelData.code, hour_col.modelData.is_day)
                                    smooth: false
                                    mipmap: false
                                }
                            }

                            Text {
                                visible: root.sub === 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.top
                                anchors.verticalCenterOffset: track.icon_row_h / 2
                                text: "▲"
                                rotation: hour_col.modelData.wind_dir
                                color: root.sub_color
                                font.pixelSize: Style.font_size
                            }

                            Text {
                                anchors.top: parent.top
                                anchors.topMargin: track.icon_row_h
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: WeatherState.format_hour(new Date(hour_col.modelData.dt)).toUpperCase()
                                color: hour_col.selected ? Style.pal.fg_strong : Style.pal.primary_light
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-8)
                                style: Text.Raised
                                styleColor: Style.text_shadow
                            }
                        }
                    }

                    underlay: [
                        Rectangle {
                            visible: root.cursor_valid
                            x: track.left_of(root.hour_cursor) + 2
                            width: track.hour_col_w - 4
                            height: track.chart_h
                            radius: 3
                            color: Qt.alpha(Style.pal.secondary, 0.14)
                        }
                    ]

                    // The cursor hand over the selected pillar, then the kart parked at its foot.
                    Column {
                        visible: root.cursor_valid
                        x: Math.round(track.x_of(root.hour_cursor)) - width / 2
                        y: root.top_of_cursor() - root.cap_h / 2 - Style.font_size - 13 + root.bob

                        Repeater {
                            model: [10, 6, 2]

                            Rectangle {
                                required property var modelData
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: modelData
                                height: 2
                                color: Style.pal.fg_strong
                            }
                        }
                    }

                    PixelSprite {
                        visible: root.cursor_valid && WeatherState.hours.length > 0
                        pixel: 2
                        colors: [Style.pal.bg_crust, Style.pal.red, Style.pal.fg_strong, Style.pal.fg_dim, Style.pal.secondary]
                        rows: ["...00000...", "..0444440..", "..0422240..", "...00000...", ".0011111100", "00111111100", "33011111033", "33.00000.33"]
                        x: Math.round(track.x_of(root.hour_cursor) - width / 2)
                        y: track.chart_h - root.amount_h - height - 1 + (root.bob === 3 ? 1 : 0)
                    }
                }
            }
        }
    }
}
