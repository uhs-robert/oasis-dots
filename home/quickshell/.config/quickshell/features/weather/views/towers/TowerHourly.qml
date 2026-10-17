import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.features.weather
import qs.features.weather.views.shared
import qs.styles.ps2.widgets

// Hourly as a PS2 tower field: one glass tower per hour on the haze floor, as tall as the sub's value.
// The cursor hour's tower is lit and its value floats above it. sub: 0 temp, 1 precip, 2 wind, 3 UV, 4 humidity.
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var cursor_row: WeatherState.hours[root.hour_cursor]
    readonly property real top_pad: 38
    readonly property real foot_h: root.sub === 1 ? Style.fs(-3) + 10 : 8
    readonly property real base_y: track.chart_h - root.foot_h
    readonly property real tower_w: 24
    // Full scale of the precipitation amount fill, in the forecast's unit.
    readonly property real amount_full: WeatherState.metric ? 5 : 0.2

    // Series that share the tower axis are included so the dashed line never leaves the field.
    readonly property var axis: {
        const hrs = WeatherState.hours;
        if (hrs.length === 0) return { lo: 0, hi: 1 };
        if (root.sub === 1 || root.sub === 4) return { lo: 0, hi: 100 };
        const values = hrs.map(track.value_of);
        if (root.sub === 3) return { lo: 0, hi: Math.max(12, Math.max(...values) + 1) };
        const all = root.sub === 0 ? values.concat(hrs.map(r => r.feels)) : root.sub === 2 ? values.concat(hrs.map(r => r.wind_gusts)) : values;
        const lo = Math.min(...all), hi = Math.max(...all);
        if (root.sub === 2) return { lo: 0, hi: Math.max(1, hi) };
        const pad = Math.max(2, (hi - lo) * 0.15);
        return { lo: lo - pad, hi: hi + pad };
    }

    function frac(v) {
        return Math.max(0, Math.min(1, (v - root.axis.lo) / ((root.axis.hi - root.axis.lo) || 1)));
    }

    function height_of(v) {
        return Math.max(4, (root.base_y - root.top_pad) * (0.06 + 0.94 * root.frac(v)));
    }

    function accent_of(row) {
        switch (root.sub) {
        case 0: return WeatherState.temp_color(row.temp);
        case 1: return Theme.info;
        case 2: return Style.pal.cyan;
        case 3: return WeatherState.uv_color(row.uv_index);
        default: return Style.pal.bright_cyan;
        }
    }

    function label_of(row) {
        const v = track.value_of(row);
        return root.sub === 3 ? v.toFixed(1) : Math.round(v) + (root.sub === 1 || root.sub === 4 ? "%" : root.sub === 0 ? "°" : "");
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

        const x_of = track.x_of;
        const base = root.base_y;
        const font_px = Style.fs(-2);

        for (const b of track.day_boundaries) {
            const x = track.left_of(b.index);
            const line = ctx.createLinearGradient(0, 0, 0, base);
            line.addColorStop(0, Qt.alpha(Theme.theme_primary_light, 0.35));
            line.addColorStop(1, Qt.alpha(Theme.theme_primary_light, 0));
            ctx.fillStyle = line;
            ctx.fillRect(x, 0, 1, base);
            ctx.fillStyle = Theme.theme_primary_light;
            ctx.font = font_px + "px \"" + Style.font_family + "\"";
            ctx.textAlign = "left";
            ctx.fillText(b.label, x + 4, 12);
        }

        const tw = root.tower_w;
        for (let i = 0; i < hrs.length; i++) {
            const row = hrs[i];
            const th = root.height_of(track.value_of(row));
            const x = x_of(i) - tw / 2;
            const y = base - th;
            const accent = root.accent_of(row);

            const body = ctx.createLinearGradient(0, y, 0, base);
            body.addColorStop(0, Qt.alpha(Theme.theme_primary_light, 0.55));
            body.addColorStop(0.3, Qt.alpha(Theme.theme_primary_strong, 0.45));
            body.addColorStop(1, Qt.alpha(Theme.theme_primary_strong, 0.14));
            ctx.fillStyle = body;
            ctx.fillRect(x, y, tw, th);

            if (root.sub === 1 && row.precip > 0) {
                const fill_h = Math.max(2, th * Math.min(1, row.precip / root.amount_full));
                const water = ctx.createLinearGradient(0, base - fill_h, 0, base);
                water.addColorStop(0, Qt.alpha(Theme.info, 0.95));
                water.addColorStop(1, Qt.alpha(Theme.info, 0.5));
                ctx.fillStyle = water;
                ctx.fillRect(x + 1, base - fill_h, tw - 2, fill_h);
            } else if (root.sub === 3) {
                ctx.fillStyle = Qt.alpha(accent, 0.3);
                ctx.fillRect(x, y, tw, th);
            }

            ctx.fillStyle = Qt.alpha(Theme.bg_shadow, 0.28);
            ctx.fillRect(x + tw * 0.62, y, tw * 0.38, th);

            const bloom = ctx.createLinearGradient(0, y - 9, 0, y);
            bloom.addColorStop(0, Qt.alpha(accent, 0));
            bloom.addColorStop(1, Qt.alpha(accent, 0.3));
            ctx.fillStyle = bloom;
            ctx.fillRect(x - 2, y - 9, tw + 4, 9);

            ctx.fillStyle = Qt.alpha(accent, 0.95);
            ctx.fillRect(x, y, tw, 2);

            if (root.sub !== 1) {
                const reflection = ctx.createLinearGradient(0, base, 0, base + 7);
                reflection.addColorStop(0, Qt.alpha(Theme.theme_primary_strong, 0.3));
                reflection.addColorStop(1, Qt.alpha(Theme.theme_primary_strong, 0));
                ctx.fillStyle = reflection;
                ctx.fillRect(x, base, tw, 7);
            }
        }

        const secondary = root.sub === 0 ? hrs.map(r => r.feels) : root.sub === 2 ? hrs.map(r => r.wind_gusts) : null;
        if (secondary) {
            ctx.setLineDash([3, 3]);
            ctx.strokeStyle = Theme.fg_strong;
            ctx.globalAlpha = 0.8;
            ctx.lineWidth = 1.2;
            ctx.beginPath();
            for (let i = 0; i < hrs.length; i++) {
                const y = base - root.height_of(secondary[i]);
                if (i === 0) ctx.moveTo(x_of(i), y); else ctx.lineTo(x_of(i), y);
            }
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.globalAlpha = 1;
        }

        ctx.font = font_px + "px \"" + Style.font_family + "\"";
        ctx.textAlign = "center";
        const amount_px = Style.fs(-3);
        for (let i = 0; i < hrs.length; i++) {
            const y = base - root.height_of(track.value_of(hrs[i]));
            ctx.fillStyle = Qt.alpha(Theme.fg_strong, 0.8);
            ctx.font = font_px + "px \"" + Style.font_family + "\"";
            ctx.fillText(root.label_of(hrs[i]), x_of(i), y - 8);
            if (root.sub === 1) {
                ctx.fillStyle = Theme.info;
                ctx.font = amount_px + "px \"" + Style.font_family + "\"";
                ctx.fillText(hrs[i].precip.toFixed(hrs[i].precip < 1 ? 2 : 1), x_of(i), track.chart_h - 2);
            }
        }
    }

    readonly property string readout: {
        const r = root.cursor_row;
        if (!r) return "";
        const parts = [WeatherState.format_hour(new Date(r.dt)), Math.round(r.temp) + "°" + WeatherState.unit_symbol(), r.pop + "% pop", r.precip.toFixed(2) + (WeatherState.metric ? " mm" : " in"), r.cond];
        if (root.sub === 0) parts.splice(2, 0, "feels " + Math.round(r.feels) + "°");
        if (root.sub === 2) parts.splice(2, 0, Math.round(r.wind_speed) + " " + WeatherState.wind_unit() + " " + WeatherState.wind_dir_label(r.wind_dir) + " gusts " + Math.round(r.wind_gusts));
        if (root.sub === 3) parts.splice(2, 0, "UV " + r.uv_index.toFixed(1));
        if (root.sub === 4) parts.splice(2, 0, r.humidity + "% humid");
        return parts.join(" · ");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(18, implicitHeight)
            text: root.readout
            color: Theme.fg_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
            font.weight: Font.Light
            elide: Text.ElideRight
        }

        HourlyTrack {
            id: track
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: 4
            hour_cursor: root.hour_cursor
            sub: root.sub
            on_select: i => root.on_select(i)
            scroll_x: root.scroll_x
            on_scroll: x => root.on_scroll(x)
            paint: root.paint
            arrow_color: Style.pal.cyan
            label_color: Theme.theme_primary_light
            label_color_selected: Theme.fg_strong
            hidpi_icons: true
            highlight: Component {
                Rectangle {
                    radius: Style.radius(6)
                    color: Style.selection_bg
                    border.width: 1
                    border.color: Style.selection_border
                }
            }

            underlay: TowerFloor {
                y: root.base_y - 28
                width: parent.width
                height: parent.height - y
                haze_h: 28
            }

            // Towers and their values are painted once; only the lit tower and its floating value are live items.
            MouseArea {
                width: parent.width
                height: track.chart_h
                onClicked: mouse => {
                    const i = Math.floor(mouse.x / track.hour_col_w);
                    if (i >= 0 && i < WeatherState.hours.length) root.on_select(i);
                }
            }

            Item {
                id: lit
                readonly property bool shown: !!root.cursor_row
                readonly property real th: root.cursor_row ? root.height_of(track.value_of(root.cursor_row)) : 0
                readonly property color accent: root.cursor_row ? root.accent_of(root.cursor_row) : Theme.info
                visible: lit.shown
                x: track.x_of(root.hour_cursor) - root.tower_w / 2
                y: root.base_y - lit.th
                width: root.tower_w
                height: lit.th

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -6
                    anchors.bottomMargin: 0
                    radius: 7
                    color: Qt.alpha(Theme.theme_primary, 0.26)
                }

                Rectangle {
                    anchors.fill: parent
                    border.width: 1
                    border.color: Qt.alpha(Theme.theme_primary_light, 0.85)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.alpha(Theme.fg_strong, 0.4) }
                        GradientStop { position: 1; color: Qt.alpha(Theme.theme_primary_light, 0.06) }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 2
                    color: Qt.lighter(lit.accent, 1.4)
                }

                // Opaque so it hides the painted value beneath it.
                Rectangle {
                    id: bubble
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: -height - 3
                    width: Math.max(root.tower_w + 12, value_text.implicitWidth + 14)
                    height: value_text.implicitHeight + 6
                    radius: height / 2
                    color: Style.frame_color
                    border.width: 1
                    border.color: Qt.alpha(Theme.theme_primary_light, 0.7)

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Qt.alpha(Theme.theme_primary, 0.22)
                    }

                    Text {
                        id: value_text
                        anchors.centerIn: parent
                        text: root.cursor_row ? root.label_of(root.cursor_row) : ""
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(0)
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}
