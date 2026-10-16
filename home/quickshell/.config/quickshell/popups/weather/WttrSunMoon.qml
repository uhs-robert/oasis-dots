import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import "WttrArt.js" as WttrArt
import "WttrSky.js" as WttrSky

// `curl wttr.in/Moon`: the moon drawn in characters at the selected day's phase beside the v2 astronomy lines,
// a text bar of the day from dawn to dusk with today's sun on it, and the Daily day window as a tab line.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property var day: WeatherState.days[Math.max(0, Math.min(WeatherState.days.length - 1, root.day_cursor))]
    readonly property bool is_today: root.day_cursor === 0
    readonly property int text_px: Style.fs(-3)
    readonly property real glyph_w: metrics.font.pixelSize > 0 ? Math.max(1, metrics.advanceWidth("─")) : 1
    readonly property int lh: Math.max(1, Math.floor(metrics.height))
    readonly property color rule: Style.text_muted
    readonly property color inverse: Style.tab_active_fg
    readonly property var moon_colors: ({ b: Theme.bright_yellow, m: Theme.yellow, d: Theme.fg_dim })

    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null })
    readonly property real moon_phase: root.day ? WeatherState.moon_phase_for_date(root.day.date) : 0
    readonly property string next_full: root.day ? WeatherState.next_full_moon_label(root.day.date) : ""

    // Re-read each minute so the sun marker moves.
    property real now_min: root.minutes_now()

    function minutes_now() {
        const loc = WeatherState.location_now();
        return loc.getUTCHours() * 60 + loc.getUTCMinutes();
    }

    function hm_minutes(hm) {
        const parts = (hm || "").split(":");
        return parts.length === 2 ? parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) : null;
    }

    function hm_of(minutes) {
        const m = Math.round(minutes);
        return String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0");
    }

    readonly property var rise_min: root.day ? root.hm_minutes(root.day.sunrise) : null
    readonly property var set_min: root.day ? root.hm_minutes(root.day.sunset) : null
    readonly property bool has_sun: root.rise_min !== null && root.set_min !== null && root.set_min > root.rise_min
    readonly property var twilight: root.day && root.has_sun ? WttrSky.civil_twilight(WeatherState.lat, WeatherState.lon, root.day.date, root.rise_min, root.set_min) : null
    readonly property var sun_fraction: root.is_today && root.has_sun && root.now_min >= root.rise_min && root.now_min <= root.set_min ? (root.now_min - root.rise_min) / (root.set_min - root.rise_min) : null

    function time_text(minutes) {
        return minutes === null || minutes === undefined ? "—" : WeatherState.fmt_hm(root.hm_of(minutes));
    }

    function day_length() {
        if (!root.has_sun) return "—";
        const mins = root.set_min - root.rise_min;
        return Math.floor(mins / 60) + "h " + (mins % 60) + "m";
    }

    function pad_key(key) {
        return key + " ".repeat(Math.max(1, 10 - key.length));
    }

    function line(key, value, key_color, value_color) {
        return WttrArt.runs([[root.pad_key(key), String(key_color)], [value, String(value_color)]]);
    }

    readonly property string astro_text: {
        const moon = WeatherState.moon_name(root.moon_phase);
        const lit = Math.round(WttrSky.illumination(root.moon_phase) * 100) + "%";
        const tw = root.twilight;
        const sun = root.has_sun;
        const rows = [
            root.line("Phase", moon, Style.text_muted, Theme.bright_yellow),
            root.line("Lit", lit, Style.text_muted, Style.text_fg),
            root.line("Moonrise", root.moon_times.rise || "—", Style.text_muted, Style.text_fg),
            root.line("Moonset", root.moon_times.set || "—", Style.text_muted, Style.text_fg),
            root.line("Full moon", root.next_full, Style.text_muted, Style.text_fg),
            "",
            root.line("Dawn", root.time_text(tw ? tw.dawn : null), Style.text_muted, Theme.fg_dim),
            root.line("Sunrise", root.time_text(sun ? root.rise_min : null), Style.text_muted, Theme.yellow),
            root.line("Zenith", root.time_text(sun ? (root.rise_min + root.set_min) / 2 : null), Style.text_muted, Theme.bright_yellow),
            root.line("Sunset", root.time_text(sun ? root.set_min : null), Style.text_muted, Theme.yellow),
            root.line("Dusk", root.time_text(tw ? tw.dusk : null), Style.text_muted, Theme.fg_dim),
            root.line("Daylight", root.day_length(), Style.text_muted, Style.text_fg)
        ];
        return rows.join("<br>");
    }

    readonly property int text_cols: 10 + 15
    // A character cell is taller than wide, so the disc takes that many columns per row to look round.
    readonly property real cell_aspect: root.lh / root.glyph_w
    readonly property int art_rows: Math.max(5, Math.min(12, Math.floor((root.width - root.text_cols * root.glyph_w - 14) / root.glyph_w / root.cell_aspect), Math.floor((root.height - 8 * root.lh) / root.lh)))
    readonly property string moon_text: WttrSky.moon_art(root.moon_phase, root.art_rows, Math.round(root.art_rows * root.cell_aspect)).map(runs => WttrArt.runs(runs.map(r => [r[0], String(root.moon_colors[r[1]])]))).join("<br>")

    readonly property int bar_chars: Math.max(10, Math.floor(root.width / root.glyph_w))

    // One character per slice of the day: night, twilight, daylight.
    readonly property string sun_bar: {
        if (!root.has_sun) return WttrArt.runs([["░".repeat(root.bar_chars), String(Theme.fg_dim)]]);
        const tw = root.twilight;
        const dawn = tw ? tw.dawn : root.rise_min, dusk = tw ? tw.dusk : root.set_min;
        const out = [];
        for (let p = 0; p < root.bar_chars; p++) {
            const m = (p + 0.5) / root.bar_chars * 1440;
            const day_part = m >= root.rise_min && m <= root.set_min;
            const dim_part = m >= dawn && m <= dusk;
            const run = day_part ? ["█", String(Theme.yellow)] : dim_part ? ["▒", String(Theme.fg_dim)] : ["░", String(Theme.fg_dim)];
            if (out.length > 0 && out[out.length - 1][1] === run[1]) out[out.length - 1][0] += run[0];
            else out.push(run);
        }
        return WttrArt.runs(out);
    }

    readonly property string tick_row: {
        const cells = new Array(root.bar_chars).fill(" ");
        for (const hour of [0, 6, 12, 18, 24]) {
            const label = String(hour).padStart(2, "0");
            const at = Math.min(root.bar_chars - label.length, Math.max(0, Math.round(hour / 24 * root.bar_chars - label.length / 2)));
            for (let i = 0; i < label.length; i++) cells[at + i] = label[i];
        }
        return cells.join("");
    }

    readonly property real marker_x: root.sun_fraction === null ? 0 : (root.rise_min + root.sun_fraction * (root.set_min - root.rise_min)) / 1440 * root.bar_chars * root.glyph_w

    Timer {
        interval: 60000
        running: root.is_today
        repeat: true
        onTriggered: root.now_min = root.minutes_now()
    }

    FontMetrics {
        id: metrics
        font.family: Style.font_family
        font.pixelSize: root.text_px
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: WttrArt.runs([["$ ", Theme.theme_secondary], ["curl wttr.in/Moon" + (root.day ? "@" + root.day.date : ""), Theme.fg_core]])
            font.family: Style.font_family
            font.pixelSize: root.text_px
        }

        // tmux-style window list: index:name, the selected one inverted and starred.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.lh + 4

            RowLayout {
                anchors.fill: parent
                spacing: 0

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
                        Layout.fillHeight: true
                        color: tab.active ? Style.tab_active_bg : "transparent"

                        Text {
                            anchors.centerIn: parent
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: tab.day_index + ":" + tab.modelData.weekday + (tab.active ? "*" : "")
                            color: tab.active ? root.inverse : Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: root.text_px
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.on_select(tab.day_index)
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: -4
            clip: true
            text: "─".repeat(root.bar_chars)
            color: root.rule
            font.family: Style.font_family
            font.pixelSize: root.text_px
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: Math.round(root.glyph_w * 2)

            Text {
                Layout.alignment: Qt.AlignTop
                textFormat: Text.StyledText
                text: root.moon_text
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: root.text_px
                lineHeight: root.lh
                lineHeightMode: Text.FixedHeight
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                textFormat: Text.StyledText
                text: root.astro_text
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: root.text_px
                lineHeight: root.lh
                lineHeightMode: Text.FixedHeight
            }
        }

        Item { Layout.fillHeight: true }

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: WttrArt.runs([["sun ", String(Style.text_muted)], [root.is_today ? (root.sun_fraction === null ? "down" : Math.round(root.sun_fraction * 100) + "% of daylight, now " + WeatherState.fmt_hm(root.hm_of(root.now_min))) : root.day ? root.day.date : "", String(Style.text_fg)]])
            font.family: Style.font_family
            font.pixelSize: root.text_px
        }

        // The marker row reserves its height on every day so the bar does not jump when the selection leaves today.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.lh

            Text {
                visible: root.sun_fraction !== null
                x: root.marker_x - width / 2
                text: "▼"
                color: Theme.bright_yellow
                font.family: Style.font_family
                font.pixelSize: root.text_px
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: -4
            textFormat: Text.StyledText
            text: root.sun_bar
            font.family: Style.font_family
            font.pixelSize: root.text_px
            lineHeight: root.lh
            lineHeightMode: Text.FixedHeight
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: -4
            text: root.tick_row
            color: Style.text_muted
            font.family: Style.font_family
            font.pixelSize: root.text_px
        }
    }
}
