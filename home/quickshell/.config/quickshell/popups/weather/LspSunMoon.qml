import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// The selected day as `:checkhealth weather` under a tabline of days: sun and moon sections of OK / WARNING lines,
// the moon phase as a Nerd Font glyph and, for today, a progress line along the sun's path.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property int text_px: Style.fs(-2)
    readonly property var day: WeatherState.days[Math.max(0, Math.min(WeatherState.days.length - 1, root.day_cursor))]
    readonly property bool is_today: root.day_cursor === 0

    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null, always_up: false, always_down: false })
    readonly property real moon_phase: root.day ? WeatherState.moon_phase_for_date(root.day.date) : 0
    readonly property string moon_key: WeatherState.moon_phase_key(root.moon_phase)
    readonly property string next_full: root.day ? WeatherState.next_full_moon_label(root.day.date) : ""
    readonly property var moon_glyphs: ({
        new: "\u{f0f64}",
        waxing_crescent: "\u{f0f67}",
        first_quarter: "\u{f0f61}",
        waxing_gibbous: "\u{f0f68}",
        full: "\u{f0f62}",
        waning_gibbous: "\u{f0f66}",
        last_quarter: "\u{f0f63}",
        waning_crescent: "\u{f0f65}"
    })
    readonly property int illumination: Math.round((1 - Math.cos(2 * Math.PI * root.moon_phase)) / 2 * 100)

    // Minutes into the location's day, refreshed each minute so today's sun status stays live.
    property real now_min: root.location_minutes()

    function location_minutes() {
        const loc = WeatherState.location_now();
        return loc.getUTCHours() * 60 + loc.getUTCMinutes();
    }

    function hm_minutes(hm) {
        const parts = (hm || "").split(":");
        return parts.length === 2 ? parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) : null;
    }

    readonly property var rise_min: root.hm_minutes(root.day ? root.day.sunrise : "")
    readonly property var set_min: root.hm_minutes(root.day ? root.day.sunset : "")
    readonly property bool has_sun: root.rise_min !== null && root.set_min !== null && root.set_min > root.rise_min
    readonly property real sun_fraction: root.has_sun ? Math.max(0, Math.min(1, (root.now_min - root.rise_min) / (root.set_min - root.rise_min))) : 0

    function duration(mins) {
        const m = Math.max(0, Math.round(mins));
        return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m";
    }

    function span(text, color, bold) {
        const safe = String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;");
        return "<font color=\"" + color + "\">" + (bold ? "<b>" + safe + "</b>" : safe) + "</font>";
    }

    // One checkhealth line: "- OK key value", the status in its health colour.
    function health(status, key, value) {
        const colors = { OK: Theme.ok, WARNING: Theme.warning, ERROR: Theme.error, ADVICE: Theme.info };
        return root.span("- ", String(Style.text_muted)) + root.span(status, String(colors[status]), true) + root.span(" " + key + " ", String(Style.text_dim)) + root.span(value, String(Style.text_fg));
    }

    readonly property var sun_lines: {
        if (!root.day) return [];
        const lines = [
            root.health("OK", "sunrise", WeatherState.fmt_hm(root.day.sunrise) || "n/a"),
            root.health("OK", "sunset", WeatherState.fmt_hm(root.day.sunset) || "n/a"),
            root.has_sun ? root.health("OK", "day length", root.duration(root.set_min - root.rise_min)) : root.health("WARNING", "day length", "unknown")
        ];
        if (root.is_today && root.has_sun) {
            if (root.now_min < root.rise_min) lines.push(root.health("WARNING", "sun has not risen", "rises in " + root.duration(root.rise_min - root.now_min)));
            else if (root.now_min > root.set_min) lines.push(root.health("WARNING", "sun has set", root.duration(root.now_min - root.set_min) + " ago"));
            else lines.push(root.health("OK", "sun is up", root.duration(root.set_min - root.now_min) + " until sunset"));
        }
        return lines;
    }

    readonly property var moon_lines: {
        if (!root.day) return [];
        const up = root.moon_times;
        const rise = up.rise || (up.always_up ? "always up" : up.always_down ? "never rises" : "none today");
        const lines = [
            root.health("OK", "phase", WeatherState.moon_name(root.moon_phase) + " (" + root.illumination + "%)"),
            up.rise || up.always_up || up.always_down ? root.health("OK", "moonrise", rise) : root.health("WARNING", "moonrise", rise)
        ];
        if (up.set) lines.push(root.health("OK", "moonset", up.set));
        lines.push(root.health("ADVICE", "next full moon", root.next_full));
        return lines;
    }

    FontMetrics {
        id: metrics
        font.family: Style.mono_font
        font.pixelSize: root.text_px
    }

    // rise ━━━━●──── set, filled to the sun's position; drawn in cells of the mono font so it fills the width exactly.
    readonly property string rise_label: root.day ? WeatherState.fmt_hm(root.day.sunrise) : ""
    readonly property string set_label: root.day ? WeatherState.fmt_hm(root.day.sunset) : ""
    readonly property int track_cells: Math.max(6, Math.floor((root.width - 24 - metrics.advanceWidth(root.rise_label + root.set_label + "  ")) / Math.max(1, metrics.advanceWidth("━"))) - 2)
    readonly property int sun_cell: Math.min(root.track_cells - 1, Math.round(root.sun_fraction * (root.track_cells - 1)))
    readonly property string progress_text: root.span(root.rise_label + " ", String(Style.text_dim))
        + root.span("━".repeat(root.sun_cell), String(Style.pal.yellow)) + root.span("●", String(Style.pal.bright_yellow))
        + root.span("─".repeat(Math.max(0, root.track_cells - root.sun_cell - 1)), String(Style.text_muted)) + root.span(" " + root.set_label, String(Style.text_dim))

    Timer {
        interval: 60000
        running: root.is_today
        repeat: true
        onTriggered: root.now_min = root.location_minutes()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            Repeater {
                model: WeatherState.days.slice(root.first_day, root.first_day + root.day_span)

                Rectangle {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property int day_index: root.first_day + tab.index
                    readonly property bool active: tab.day_index === root.day_cursor

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: tab_text.implicitHeight + 8
                    color: tab.active ? Style.pal.visual_bg : Style.tab_bg

                    Rectangle {
                        visible: tab.active
                        width: parent.width
                        height: 2
                        color: Style.tab_marker
                    }

                    Text {
                        id: tab_text
                        anchors.centerIn: parent
                        width: parent.width - 8
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: tab.modelData.weekday
                        color: tab.active ? Style.text_strong : Style.tab_fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-3)
                        font.bold: tab.active
                        font.italic: !tab.active
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(tab.day_index)
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Column {
                id: report
                x: 6
                width: parent.width - 12
                spacing: 3

                Text {
                    text: ":checkhealth weather"
                    color: Style.text_dim
                    font.family: Style.mono_font
                    font.pixelSize: root.text_px
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    topPadding: 2
                    textFormat: Text.StyledText
                    text: root.span("weather: ", String(Style.pal.primary), true) + root.span("health check  ", String(Style.text_strong), true) + root.span(root.day ? root.day.date : "", String(Style.text_dim))
                    color: Style.text_fg
                    font.family: Style.mono_font
                    font.pixelSize: root.text_px
                }

                Text {
                    topPadding: 4
                    textFormat: Text.StyledText
                    text: root.span("sun ~", String(Style.pal.yellow), true)
                    color: Style.text_fg
                    font.family: Style.mono_font
                    font.pixelSize: root.text_px
                }

                Repeater {
                    model: root.sun_lines

                    Text {
                        required property string modelData
                        width: report.width
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: modelData
                        color: Style.text_fg
                        font.family: Style.mono_font
                        font.pixelSize: root.text_px
                    }
                }

                Text {
                    visible: root.is_today && root.has_sun
                    width: parent.width
                    topPadding: 2
                    textFormat: Text.StyledText
                    text: root.progress_text
                    color: Style.text_fg
                    font.family: Style.mono_font
                    font.pixelSize: root.text_px
                }

                Item {
                    width: parent.width
                    height: moon_col.height + 8

                    Column {
                        id: moon_col
                        y: 8
                        width: parent.width
                        spacing: 3

                        Text {
                            textFormat: Text.StyledText
                            text: root.span("moon ~", String(Style.pal.bright_blue), true)
                            color: Style.text_fg
                            font.family: Style.mono_font
                            font.pixelSize: root.text_px
                        }

                        Repeater {
                            model: root.moon_lines

                            Text {
                                required property string modelData
                                width: moon_col.width - moon_glyph.width - 8
                                elide: Text.ElideRight
                                textFormat: Text.StyledText
                                text: modelData
                                color: Style.text_fg
                                font.family: Style.mono_font
                                font.pixelSize: root.text_px
                            }
                        }
                    }

                    Text {
                        id: moon_glyph
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: moon_col.verticalCenter
                        text: root.moon_glyphs[root.moon_key]
                        color: Style.pal.bright_blue
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(18)
                    }
                }
            }
        }
    }
}
