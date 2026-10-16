import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../theme/Watch.js" as W

// Hourly as the pause watch's dial: 12-hour pages counted from the forecast's first hour, so the bezel is always full and a page may start at any clock hour. Each hour is a bar at its
// real clock position growing outward from the band's inner edge, its length and brightness carrying the sub's value; the hand sits on the cursor hour and its readings on the face.
// A seam notch marks the page's start, which tells 8 a.m. from 8 p.m. The page follows the cursor, so crossing its edge flips pages.
// sub: 0 temp, 1 precip (chance + amount), 2 wind, 3 UV, 4 humidity. h/l move the hour cursor, H/L a day; the popup owns the cursor.
Item {
    id: root

    property int hour_cursor: 0
    property int sub: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}
    // The dial never scrolls; these keep the shared view's interface for the popup.
    property real scroll_x: 0
    property var on_scroll: function (x) {}

    readonly property var sub_names: ["Temp", "Precip", "Wind", "UV", "Humid"]
    readonly property var hours: WeatherState.hours
    readonly property var cursor_row: root.hours[root.hour_cursor]
    readonly property int page_start: Math.floor(root.hour_cursor / 12) * 12
    // Clock hour of hours[0]; empty slots past the forecast's end continue counting from it.
    readonly property int first_clock_hour: root.hours.length ? root.hours[0].hour : 0
    readonly property real tick_min: 3
    readonly property real tick_w: 26
    // Room left above the tallest bar for the peak hour's printed value.
    readonly property real label_room: 20
    readonly property real bar_base: face.bezel_r - face.band + 2
    readonly property real bar_span: face.band - 4 - root.label_room - root.tick_min

    function scroll_to_cursor() {}
    function request_scroll() {}

    readonly property var window_rows: root.hours.slice(root.page_start, root.page_start + 12)

    // Temp scales to the shown page's own range, padded, so its shape fills the band; the rest use fixed ranges
    // so 80% rain is long on any day.
    function range_of(pick, floor_span) {
        if (!root.window_rows.length) return { lo: 0, hi: floor_span };
        const vals = root.window_rows.map(pick);
        const lo = Math.min(...vals);
        const hi = Math.max(...vals);
        const pad = Math.max((hi - lo) * 0.1, floor_span * 0.1);
        const mid = (lo + hi) / 2;
        const half = Math.max((hi - lo) / 2 + pad, floor_span / 2);
        return { lo: mid - half, hi: mid + half };
    }

    readonly property var temp_range: root.range_of(r => r.temp, 10)
    // Wind starts at calm so a sustained speed under every gust still draws; the top leaves room for the gust notch.
    readonly property var wind_range: ({ lo: 0, hi: Math.max(10, ...root.window_rows.map(r => Math.max(r.wind_speed, r.wind_gusts))) * 1.1 })
    readonly property real precip_max: Math.max(0.1, ...root.window_rows.map(r => r.precip))
    readonly property real uv_top: Math.max(11, ...root.window_rows.map(r => r.uv_index))

    function unit_span(v, range) {
        return Math.max(0, Math.min(1, (v - range.lo) / (range.hi - range.lo)));
    }

    function norm_of(row) {
        switch (root.sub) {
        case 0: return root.unit_span(row.temp, root.temp_range);
        case 1: return row.pop / 100;
        case 2: return root.unit_span(row.wind_speed, root.wind_range);
        case 3: return row.uv_index / root.uv_top;
        default: return row.humidity / 100;
        }
    }

    // The hour the eye should land on; a series that never leaves the floor has none.
    readonly property int peak_index: {
        let best = -1;
        let best_v = 0.02;
        for (let i = 0; i < root.window_rows.length; i++) {
            const v = root.norm_of(root.window_rows[i]);
            if (v > best_v) {
                best = i;
                best_v = v;
            }
        }
        return best;
    }

    // Temperature takes its actual band so a cold page never reads hot; the bar lengths still fill the page's own range.
    function bar_color(row, norm) {
        return root.sub === 0 ? WeatherState.temp_color(row.temp) : root.ramp_color(norm);
    }

    function ramp_color(norm) {
        const i = Math.max(0, Math.min(7, Math.round(norm * 7)));
        if (root.sub === 3) return W.warm[7 - i];
        return root.sub === 2 ? Style.wk.bar_on : W.cold_lit[i];
    }

    readonly property string temp_unit: "°" + WeatherState.unit_symbol()
    readonly property string precip_unit: WeatherState.metric ? " mm" : " in"

    function big_value(row) {
        switch (root.sub) {
        case 0: return Math.round(row.temp) + "°";
        case 1: return row.pop + "%";
        case 2: return String(Math.round(row.wind_speed));
        case 3: return row.uv_index.toFixed(1);
        default: return row.humidity + "%";
        }
    }

    function extra_line(row) {
        switch (root.sub) {
        case 0: return "FEELS " + Math.round(row.feels) + "°";
        case 1: return row.precip.toFixed(2) + root.precip_unit;
        case 2: return "GUST " + Math.round(row.wind_gusts) + " " + WeatherState.wind_unit() + " " + WeatherState.wind_dir_label(row.wind_dir);
        case 3: return WeatherState.uv_band(row.uv_index).label.toUpperCase();
        default: return "";
        }
    }

    WatchFace {
        id: face
        anchors.fill: parent
        hand_hour: root.cursor_row ? root.cursor_row.hour : -1
        seam_hour: root.window_rows.length ? root.window_rows[0].hour : -1
        band: 60

        bezel: Repeater {
            model: 12

            Item {
                id: slot
                required property int index
                readonly property var row: root.hours[root.page_start + slot.index]
                readonly property bool at_cursor: root.page_start + slot.index === root.hour_cursor
                readonly property bool is_peak: slot.index === root.peak_index
                readonly property real hour: slot.row ? slot.row.hour : (root.first_clock_hour + root.page_start + slot.index) % 24
                readonly property real norm: slot.row ? Math.max(0, Math.min(1, root.norm_of(slot.row))) : 0
                readonly property real len: root.tick_min + slot.norm * root.bar_span
                rotation: face.angle_of(slot.hour)

                Rectangle {
                    visible: slot.at_cursor
                    x: -30
                    y: -face.bezel_r + 2
                    width: 60
                    height: face.band
                    radius: 3
                    color: Qt.alpha(Style.wk.lit, 0.18)
                }

                Rectangle {
                    visible: !slot.row
                    x: -root.tick_w / 2
                    y: -root.bar_base - root.tick_min
                    width: root.tick_w
                    height: root.tick_min
                    color: Style.wk.bar_off
                }

                Rectangle {
                    visible: !!slot.row
                    x: root.sub === 1 ? -root.tick_w / 2 - 3 : -root.tick_w / 2
                    y: -root.bar_base - slot.len
                    width: root.tick_w
                    height: slot.len
                    color: slot.at_cursor ? W.white : root.bar_color(slot.row, slot.norm)
                    opacity: slot.at_cursor ? 1 : 0.3 + 0.7 * slot.norm
                }

                Rectangle {
                    visible: !!slot.row && slot.is_peak
                    x: root.sub === 1 ? -root.tick_w / 2 - 3 : -root.tick_w / 2
                    y: -root.bar_base - slot.len - 2
                    width: root.tick_w
                    height: 2
                    color: W.white
                }

                Rectangle {
                    visible: !!slot.row && root.sub === 1
                    x: root.tick_w / 2 - 1
                    y: -root.bar_base - (slot.row ? root.tick_min + Math.min(1, slot.row.precip / root.precip_max) * root.bar_span : 0)
                    width: 5
                    height: slot.row ? root.tick_min + Math.min(1, slot.row.precip / root.precip_max) * root.bar_span : 0
                    color: Style.wk.lit
                    opacity: slot.at_cursor ? 1 : 0.7
                }

                Rectangle {
                    visible: !!slot.row && root.sub === 2
                    x: -root.tick_w / 2
                    y: -root.bar_base - (slot.row ? root.tick_min + root.unit_span(slot.row.wind_gusts, root.wind_range) * root.bar_span : 0)
                    width: root.tick_w
                    height: 2
                    color: Style.wk.lit
                    opacity: 0.9
                }

                Text {
                    visible: !!slot.row && slot.is_peak
                    x: -width / 2
                    y: -root.bar_base - slot.len - 8 - height / 2
                    text: slot.row ? root.big_value(slot.row) : ""
                    color: W.white
                    font.family: W.mono_font
                    font.pixelSize: Style.fs(-6)
                    font.bold: true
                    rotation: -slot.rotation
                    transformOrigin: Item.Center
                }

                MouseArea {
                    x: -28
                    y: -face.bezel_r
                    width: 56
                    height: face.band
                    enabled: !!slot.row
                    onClicked: root.on_select(root.page_start + slot.index)
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 8
            spacing: 2

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: date_label.implicitWidth + 14
                implicitHeight: date_label.implicitHeight + 4
                color: W.black
                border.width: 1
                border.color: Style.wk.rim

                Text {
                    id: date_label
                    anchors.centerIn: parent
                    text: face.span_text(root.window_rows[0], root.window_rows[root.window_rows.length - 1])
                    color: Style.wk.mid
                    font.family: W.mono_font
                    font.pixelSize: Style.fs(-4)
                    font.letterSpacing: 1
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                WeatherIcon {
                    size: 30
                    code: root.cursor_row ? root.cursor_row.code : 0
                    is_day: root.cursor_row ? root.cursor_row.is_day : 1
                    tint: Style.wk.lit
                }

                Text {
                    text: root.cursor_row ? TimeFormat.hour_of(root.cursor_row.hour) : ""
                    color: Style.wk.lit
                    font.family: W.mono_font
                    font.pixelSize: Style.fs(3)
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.cursor_row ? root.big_value(root.cursor_row) : "--"
                color: root.cursor_row ? root.bar_color(root.cursor_row, root.norm_of(root.cursor_row)) : Style.wk.dim
                font.family: W.digit_font
                font.pixelSize: Style.fs(9)
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.sub_names[root.sub].toUpperCase() + (root.cursor_row && root.extra_line(root.cursor_row) !== "" ? " · " + root.extra_line(root.cursor_row) : "")
                color: Style.wk.mid
                font.family: W.mono_font
                font.pixelSize: Style.fs(-4)
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.cursor_row ? Math.round(root.cursor_row.temp) + root.temp_unit + " · " + root.cursor_row.pop + "% · " + root.cursor_row.precip.toFixed(2) + root.precip_unit : ""
                color: Style.wk.soft
                font.family: W.mono_font
                font.pixelSize: Style.fs(-4)
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.cursor_row ? root.cursor_row.cond : ""
                color: Style.wk.soft
                font.family: W.mono_font
                font.pixelSize: Style.fs(-4)
            }
        }
    }
}
