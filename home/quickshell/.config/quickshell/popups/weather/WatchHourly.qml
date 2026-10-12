// home/quickshell/.config/quickshell/popups/weather/WatchHourly.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../../theme/Watch.js" as W

// Hourly as the pause watch's 24-hour dial: the cursor's day-long window around the bezel, each hour a tick whose length and
// brightness carry the sub's value, the hand on the cursor hour and its readings on the face.
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
    readonly property int window_start: Math.floor(Math.max(0, root.hour_cursor) / 24) * 24
    readonly property var cursor_row: root.hours[root.hour_cursor]
    readonly property var first_row: root.hours[root.window_start]
    readonly property real tick_min: 5
    readonly property real tick_w: 6

    function scroll_to_cursor() {}
    function request_scroll() {}

    // Scales span every hour so a tick's length compares across windows.
    function series_max(pick, floor_v) {
        let top = floor_v;
        for (const r of root.hours) top = Math.max(top, pick(r));
        return top;
    }

    readonly property real temp_min: root.hours.length ? Math.min(...root.hours.map(r => r.temp)) : 0
    readonly property real temp_max: root.hours.length ? Math.max(...root.hours.map(r => r.temp)) : 1
    readonly property real precip_max: root.series_max(r => r.precip, 0.1)
    // Speed sets the scale, so calm hours still show; a gust past it pins its cap to the band's inner end.
    readonly property real wind_top: root.series_max(r => r.wind_speed, 1) * 1.25
    readonly property real uv_top: root.series_max(r => r.uv_index, 12)

    function norm_of(row) {
        switch (root.sub) {
        case 0: return (row.temp - root.temp_min) / Math.max(1, root.temp_max - root.temp_min);
        case 1: return row.pop / 100;
        case 2: return row.wind_speed / root.wind_top;
        case 3: return row.uv_index / root.uv_top;
        default: return row.humidity / 100;
        }
    }

    function ramp_color(norm) {
        const i = Math.max(0, Math.min(7, Math.round(norm * 7)));
        if (root.sub === 0 || root.sub === 3) return W.warm[7 - i];
        // The lowest blues vanish against the dial, so the cold ramp starts a step up.
        return root.sub === 2 ? Style.wk.bar_on : W.cold_lit[Math.min(7, i + 2)];
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

    function date_text() {
        if (!root.cursor_row || !root.first_row) return "";
        const day = d => Qt.formatDate(new Date(d + "T00:00:00"), "ddd d").toUpperCase();
        const last = root.hours[Math.min(root.hours.length - 1, root.window_start + 23)];
        return day(root.first_row.date) + (last.date !== root.first_row.date ? " > " + day(last.date) : "");
    }

    WatchFace {
        id: face
        anchors.fill: parent
        hand_hour: root.cursor_row ? root.cursor_row.hour : -1

        bezel: Repeater {
            model: 24

            Item {
                id: slot
                required property int index
                readonly property var row: root.hours[root.window_start + slot.index]
                readonly property bool at_cursor: root.window_start + slot.index === root.hour_cursor
                readonly property real hour: slot.row ? slot.row.hour : ((root.first_row ? root.first_row.hour : 0) + slot.index) % 24
                readonly property real norm: slot.row ? Math.max(0, Math.min(1, root.norm_of(slot.row))) : 0
                readonly property real len: root.tick_min + slot.norm * (face.band - 4 - root.tick_min)
                rotation: face.angle_of(slot.hour)

                Rectangle {
                    visible: slot.at_cursor
                    x: -15
                    y: -face.bezel_r + 2
                    width: 30
                    height: face.band
                    radius: 3
                    color: Qt.alpha(Style.wk.lit, 0.18)
                }

                Rectangle {
                    visible: !slot.row
                    x: -root.tick_w / 2
                    y: -face.bezel_r + 4
                    width: root.tick_w
                    height: root.tick_min
                    color: Style.wk.bar_off
                }

                Rectangle {
                    visible: !!slot.row
                    x: root.sub === 1 ? -root.tick_w : -root.tick_w / 2
                    y: -face.bezel_r + 4
                    width: root.tick_w
                    height: slot.len
                    color: slot.at_cursor ? W.white : root.ramp_color(slot.norm)
                    opacity: slot.at_cursor ? 1 : 0.5 + 0.5 * slot.norm
                }

                Rectangle {
                    visible: !!slot.row && root.sub === 1
                    x: 1
                    y: -face.bezel_r + 4
                    width: 3
                    height: slot.row ? root.tick_min + Math.min(1, slot.row.precip / root.precip_max) * (face.band - 4 - root.tick_min) : 0
                    color: Style.wk.lit
                    opacity: slot.at_cursor ? 1 : 0.7
                }

                Rectangle {
                    visible: !!slot.row && root.sub === 2
                    x: -root.tick_w / 2
                    y: -face.bezel_r + 4 + (slot.row ? root.tick_min + Math.min(1, slot.row.wind_gusts / root.wind_top) * (face.band - 4 - root.tick_min) : 0)
                    width: root.tick_w
                    height: 2
                    color: Style.wk.lit
                    opacity: 0.9
                }

                MouseArea {
                    x: -13
                    y: -face.bezel_r
                    width: 26
                    height: face.band
                    enabled: !!slot.row
                    onClicked: root.on_select(root.window_start + slot.index)
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 16
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
                    text: root.date_text()
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
                    text: root.cursor_row ? WeatherState.format_hour(new Date(root.cursor_row.dt)) : ""
                    color: Style.wk.lit
                    font.family: W.mono_font
                    font.pixelSize: Style.fs(3)
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.cursor_row ? root.big_value(root.cursor_row) : "--"
                color: root.cursor_row ? root.ramp_color(root.norm_of(root.cursor_row)) : Style.wk.dim
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
