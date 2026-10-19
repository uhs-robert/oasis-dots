import QtQuick
import QtQuick.Layouts
import qs.ui.frames
import qs.theme
import qs.styles.reticle.widgets
import qs.features.weather
import qs.features.weather.views.shared
import qs.styles.metroid.widgets
import qs.features.popups

// A Scan Visor waveform readout: the hours as a glowing trace over a hex lattice, the cursor hour locked on by scan brackets and a reticle.
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

    readonly property color visor: Style.pal.primary
    readonly property color visor_light: Style.pal.primary_light
    readonly property color rain: Theme.info
    readonly property int legend_h: 18
    readonly property int bezel: 5
    readonly property real top_pad: 22
    readonly property real amount_px: Style.fs(-4)
    readonly property real bottom_pad: root.sub === 1 ? root.amount_px + 8 : 6
    // Heavy rain in the forecast's own unit, so amount bars read the same in mm and inches.
    readonly property real precip_full_scale: WeatherState.metric ? 5 : 0.2
    readonly property bool shown: root.visible && Popups.open_name === "weather"

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]
    readonly property bool has_cursor: !!root.cursor_row
    // The dashed trace shares the axis, so feels-like and gusts are part of the range.
    readonly property var scale: root.scale_range(WeatherState.hours, root.sub)

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

    function value_text(v) {
        if (root.sub === 3) return v.toFixed(1);
        return Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
    }

    function unit_text() {
        return ["°" + WeatherState.unit_symbol(), "% CHANCE", WeatherState.wind_unit().toUpperCase(), "UV", "% RH"][root.sub];
    }

    function secondary_name() {
        return root.sub === 0 ? "FEELS" : root.sub === 2 ? "GUSTS" : "";
    }

    function span_text() {
        if (root.sub === 1 || root.sub === 4 || WeatherState.hours.length === 0) return "";
        const hrs = WeatherState.hours;
        const values = hrs.map(track.value_of);
        return root.value_text(Math.min(...values)) + " - " + root.value_text(Math.max(...values));
    }

    function scroll_to_cursor() {
        track.scroll_to_cursor();
    }

    function request_scroll() {
        track.request_scroll();
    }

    // A pointy-top hex lattice whose column pitch is half an hour column, so hour lines fall on hex edges.
    // Only three edges per hex are stroked, so the shared ones are not drawn twice.
    function paint_lattice(ctx, w, h) {
        const pitch = track.hour_col_w / 2;
        const r = pitch / Math.sqrt(3);
        const row_h = r * 1.5;
        ctx.strokeStyle = root.visor;
        ctx.globalAlpha = 0.09;
        ctx.lineWidth = 1;
        ctx.beginPath();
        for (let j = 0; j * row_h < h + r; j++) {
            const cy = j * row_h;
            const shift = j % 2 === 1 ? pitch / 2 : 0;
            for (let cx = shift; cx < w + pitch; cx += pitch) {
                ctx.moveTo(cx - pitch / 2, cy - r / 2);
                ctx.lineTo(cx, cy - r);
                ctx.lineTo(cx + pitch / 2, cy - r / 2);
                ctx.moveTo(cx - pitch / 2, cy - r / 2);
                ctx.lineTo(cx - pitch / 2, cy + r / 2);
            }
        }
        ctx.stroke();
        ctx.globalAlpha = 0.05;
        ctx.fillStyle = root.visor_light;
        for (let y = 0; y < h; y += 4) ctx.fillRect(0, y, w, 1);
        ctx.globalAlpha = 1;
    }

    function paint(ctx, w, h) {
        ctx.reset();
        root.paint_lattice(ctx, w, h);
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return;

        const values = hrs.map(track.value_of);
        const x_of = track.x_of;
        const y_of = v => root.y_at(v, h);
        const base_y = h - root.bottom_pad;

        // Hour ticks along the baseline, a taller one every six hours.
        ctx.strokeStyle = root.visor_light;
        ctx.lineWidth = 1;
        for (let i = 0; i < hrs.length; i++) {
            const x = Math.round(x_of(i)) + 0.5;
            ctx.globalAlpha = hrs[i].hour % 6 === 0 ? 0.55 : 0.25;
            ctx.beginPath();
            ctx.moveTo(x, base_y);
            ctx.lineTo(x, base_y - (hrs[i].hour % 6 === 0 ? 6 : 3));
            ctx.stroke();
        }
        ctx.globalAlpha = 0.5;
        ctx.beginPath();
        ctx.moveTo(0, base_y + 0.5);
        ctx.lineTo(w, base_y + 0.5);
        ctx.stroke();

        ctx.strokeStyle = root.visor_light;
        ctx.globalAlpha = 0.5;
        for (const b of track.day_boundaries) {
            const x = Math.round(track.left_of(b.index)) + 0.5;
            ctx.beginPath();
            ctx.setLineDash([2, 3]);
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
            ctx.setLineDash([]);
        }
        ctx.globalAlpha = 1;
        ctx.fillStyle = root.visor_light;
        ctx.font = Style.fs(-4) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "left";
        for (const b of track.day_boundaries) ctx.fillText(b.label, track.left_of(b.index) + 4, 13);

        if (root.sub === 1) {
            ctx.fillStyle = root.rain;
            for (let i = 0; i < hrs.length; i++) {
                if (hrs[i].precip <= 0) continue;
                const bar_h = Math.max(1, Math.min(1, hrs[i].precip / root.precip_full_scale) * 14);
                ctx.globalAlpha = 0.55;
                ctx.fillRect(x_of(i) - 6, base_y - bar_h, 12, bar_h);
            }
            ctx.globalAlpha = 0.12;
            ctx.beginPath();
            ctx.moveTo(x_of(0), base_y);
            for (let i = 0; i < hrs.length; i++) ctx.lineTo(x_of(i), y_of(hrs[i].pop));
            ctx.lineTo(x_of(hrs.length - 1), base_y);
            ctx.closePath();
            ctx.fillStyle = root.visor;
            ctx.fill();
            ctx.globalAlpha = 1;
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

        // Glow: the trace wide and faint, then thin and bright.
        ctx.strokeStyle = root.visor_light;
        ctx.lineJoin = "round";
        for (const pass of [[7, 0.1], [4, 0.2], [1.3, 1]]) {
            ctx.lineWidth = pass[0];
            ctx.globalAlpha = pass[1];
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                if (i === 0) ctx.moveTo(x_of(i), y_of(values[i])); else ctx.lineTo(x_of(i), y_of(values[i]));
            }
            ctx.stroke();
        }
        ctx.globalAlpha = 1;

        // Sample markers are small diamonds; UV samples take their band's colour.
        for (let i = 0; i < hrs.length; i++) {
            const x = x_of(i), y = y_of(values[i]);
            ctx.fillStyle = root.sub === 3 ? WeatherState.uv_color(values[i]) : root.visor_light;
            ctx.beginPath();
            ctx.moveTo(x, y - 2.5);
            ctx.lineTo(x + 2.5, y);
            ctx.lineTo(x, y + 2.5);
            ctx.lineTo(x - 2.5, y);
            ctx.closePath();
            ctx.fill();
        }

        ctx.fillStyle = Style.pal.fg_strong;
        ctx.font = Style.fs(-4) + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "center";
        for (let i = 0; i < hrs.length; i++) ctx.fillText(root.value_text(values[i]), x_of(i), Math.max(13, y_of(values[i]) - 8));

        if (root.sub === 1) {
            ctx.fillStyle = root.rain;
            ctx.font = root.amount_px + "px \"" + Style.font_family + "\"";
            for (let i = 0; i < hrs.length; i++) ctx.fillText(hrs[i].precip.toFixed(hrs[i].precip < 1 ? 2 : 1), x_of(i), h - 2);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // Cursor readout: "SCAN DATA - 9PM - 76F" with the channel's value at the cursor, then the rest of the hour's conditions.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: readout_lines.implicitHeight

            Column {
                id: readout_lines
                anchors.left: parent.left
                anchors.right: reading.visible ? reading.left : parent.right
                anchors.rightMargin: reading.visible ? 8 : 0
                spacing: 1

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: !root.has_cursor ? "SCAN DATA · NO SIGNAL" : "SCAN DATA · " + WeatherState.format_hour(new Date(root.cursor_row.dt)).toUpperCase() + " · " + Math.round(root.cursor_row.temp) + "°" + WeatherState.unit_symbol()
                    color: Theme.theme_primary
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                    font.letterSpacing: 1.5
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: !root.has_cursor ? "" : (root.cursor_row.pop + "% pop · " + root.cursor_row.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in") + " · " + root.cursor_row.cond).toUpperCase()
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                    font.letterSpacing: 0.8
                }
            }

            Text {
                id: reading
                visible: root.has_cursor && root.sub !== 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.has_cursor ? root.value_text(track.value_of(root.cursor_row)) + (root.sub === 2 ? " " + WeatherState.wind_unit() : "") : ""
                color: Style.pal.fg_strong
                font.family: Style.number_font
                font.pixelSize: Style.fs(2)
            }
        }

        // The visor pane: HUD brackets around a channel legend and the scrolling trace.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Qt.alpha(root.visor, 0.03)
            border.width: 1
            border.color: Qt.alpha(root.visor, 0.28)

            Item {
                anchors.fill: parent
                anchors.margins: root.bezel

                RowLayout {
                    id: legend
                    width: parent.width
                    height: root.legend_h
                    spacing: 6

                    Rectangle {
                        Layout.preferredWidth: 5
                        Layout.preferredHeight: 5
                        rotation: 45
                        color: root.visor_light
                    }

                    Text {
                        text: root.channel_names[root.sub]
                        color: root.visor_light
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                        font.letterSpacing: 2
                    }

                    Text {
                        text: root.unit_text()
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                        font.letterSpacing: 1.5
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: root.secondary_name() !== ""
                        text: "- - " + root.secondary_name()
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                        font.letterSpacing: 1.5
                    }

                    Text {
                        visible: root.sub === 1
                        text: WeatherState.metric ? "MM / HR" : "IN / HR"
                        color: root.rain
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                        font.letterSpacing: 1.5
                    }

                    Text {
                        visible: root.span_text() !== "" && root.secondary_name() === "" && root.width >= 300
                        text: "SPAN " + root.span_text()
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                        font.letterSpacing: 1
                    }
                }

                HourlyTrack {
                    id: track
                    y: root.legend_h
                    width: parent.width
                    height: parent.height - root.legend_h
                    icon_row_h: 28
                    hour_cursor: root.hour_cursor
                    sub: root.sub
                    on_select: i => root.on_select(i)
                    scroll_x: root.scroll_x
                    on_scroll: x => root.on_scroll(x)
                    paint: root.paint
                    caps_day_labels: true
                    arrow_color: root.visor_light
                    label_color: Style.text_muted
                    label_color_selected: Style.pal.fg_strong
                    label_font_family: Style.number_font
                    label_px: Style.fs(-4)

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
                            opacity: hour_col.selected ? 1 : 0.7

                            WeatherIcon {
                                visible: root.sub !== 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: track.icon_row_h - 4
                                code: hour_col.modelData.code
                                is_day: hour_col.modelData.is_day
                            }

                            Text {
                                visible: root.sub === 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: (track.icon_row_h - height) / 2
                                text: "▲"
                                rotation: hour_col.modelData.wind_dir
                                color: root.visor_light
                                font.pixelSize: Style.font_size
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: track.icon_row_h
                                text: WeatherState.format_hour(new Date(hour_col.modelData.dt))
                                color: hour_col.selected ? Style.pal.fg_strong : Style.text_muted
                                font.family: Style.number_font
                                font.pixelSize: Style.fs(-4)
                            }
                        }
                    }

                    // The lock follows the cursor: each selection builds a fresh one, so the brackets close in every time.
                    Repeater {
                        model: WeatherState.hours.length

                        Loader {
                            required property int index
                            active: index === root.hour_cursor
                            x: track.left_of(index)
                            width: track.hour_col_w
                            height: track.height

                            sourceComponent: Item {
                                anchors.fill: parent

                                ScanLock {
                                    shown: root.shown
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: Qt.alpha(root.visor, 0.07)
                                }

                                Reticle {
                                    id: reticle
                                    readonly property real y_center: root.has_cursor ? root.y_at(track.value_of(root.cursor_row), track.chart_h) : 0
                                    width: 24
                                    height: 24
                                    x: (parent.width - width) / 2
                                    y: reticle.y_center - height / 2
                                    color: root.visor_light
                                    center_color: root.visor_light

                                    NumberAnimation on rotation {
                                        running: root.shown
                                        loops: Animation.Infinite
                                        from: 0
                                        to: 360
                                        duration: 9000
                                    }
                                }
                            }
                        }
                    }
                }
            }

            CornerBrackets {
                anchors.fill: parent
                color: Qt.alpha(root.visor, 0.75)
                inset: 0
                arm: 10
                thickness: 1.5
                all_corners: true
            }
        }
    }
}
