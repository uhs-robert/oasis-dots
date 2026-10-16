import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import "WttrArt.js" as WttrArt

// `curl wttr.in`: the condition's ASCII drawing beside the current readings, coloured like the terminal report.
ColumnLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property bool celsius: WeatherState.metric
    readonly property int text_px: Style.fs(-4)
    readonly property var art_colors: ({ y: Theme.yellow, c: Qt.tint(Theme.fg_core, Qt.alpha(Theme.fg_dim, 0.55)), d: Theme.fg_dim, r: Theme.blue, s: Theme.fg_strong, t: Theme.bright_yellow, f: Theme.fg_dim, u: Theme.fg_muted })
    readonly property var art: WttrArt.arts[root.has ? WttrArt.kind(root.cur.code) : "unknown"]
    // Keys only when the art, a key column and the longest value all fit on one row.
    readonly property bool keyed: root.width >= art_text.implicitWidth + 12 + text_metrics.advanceWidth("precip " + "+100(100) °F")
    readonly property var arrows: ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]

    function signed(t) {
        const n = Math.round(t);
        return (n > 0 ? "+" : "") + n;
    }

    function wind_color(speed) {
        const kmh = root.celsius ? speed : speed * 1.609;
        return kmh < 10 ? Theme.ok : kmh < 25 ? Theme.yellow : kmh < 45 ? Theme.bright_yellow : Theme.red;
    }

    readonly property real key_px: text_metrics.advanceWidth("precip ")
    // Bars give up cells before the value column runs out of room; unkeyed rows also carry their key after the value.
    readonly property int bar_cells: Math.max(4, Math.min(10, Math.floor((root.width - art_text.implicitWidth - 12 - (root.keyed ? root.key_px : 0) - text_metrics.advanceWidth("[] 100%" + (root.keyed ? "" : " rain"))) / text_metrics.advanceWidth("█"))))

    function key_suffix(key) {
        return root.keyed ? ["", ""] : [" " + key, Style.text_muted];
    }

    function bar(vital) {
        const lit = Math.round(vital.fill * root.bar_cells);
        return WttrArt.runs([["[", Theme.fg_dim], ["█".repeat(lit), vital.color], ["░".repeat(root.bar_cells - lit), Theme.fg_dim], ["] ", Theme.fg_dim], [vital.value + vital.unit, ""], root.key_suffix(vital.key)]);
    }

    // Today's low to high with a dot where now sits; the line is lit up to it.
    function range_line() {
        const at = Math.round(WeatherState.temp_range_pos * (root.bar_cells - 1));
        const now_color = WeatherState.temp_color(root.cur.temp);
        return WttrArt.runs([[String(Math.round(WeatherState.today_low)) + " ", WeatherState.temp_color(WeatherState.today_low)], ["━".repeat(at), now_color], ["●", Theme.fg_strong], ["━".repeat(root.bar_cells - 1 - at), Theme.fg_dim], [" " + Math.round(WeatherState.today_high), WeatherState.temp_color(WeatherState.today_high)], [" °" + WeatherState.unit_symbol(), ""]]);
    }

    function readout(vital) {
        return WttrArt.runs([[vital.value + " ", vital.color], [vital.detail.toLowerCase(), ""], root.key_suffix(vital.key)]);
    }

    readonly property bool show_vitals: root.has && WeatherState.has_vitals
    readonly property var rows: !root.has ? [] : [
        ["temp", WttrArt.runs([[root.signed(root.cur.temp), WeatherState.temp_color(root.cur.temp)], ["(", ""], [String(Math.round(root.cur.feels)), WeatherState.temp_color(root.cur.feels)], [") °" + WeatherState.unit_symbol(), ""]])]
    ].concat(root.show_vitals ? [["range", root.range_line()]] : [], [
        ["wind", WttrArt.runs([[root.arrows[Math.round(((root.cur.wind_dir % 360) + 360) % 360 / 45) % 8] + " ", Theme.fg_strong], [String(Math.round(root.cur.wind_speed)), root.wind_color(root.cur.wind_speed)], [" " + WeatherState.wind_unit(), ""]])],
        ["hum", root.show_vitals ? root.bar(WeatherState.vital("hum")) : WttrArt.runs([[root.cur.humidity + "%", ""]])]
    ], root.show_vitals ? [["rain", root.bar(WeatherState.vital("rain"))]] : [], [
        ["precip", WttrArt.runs([[root.celsius ? root.cur.precip.toFixed(1) + " mm" : root.cur.precip.toFixed(2) + " in", ""]])]
    ], root.show_vitals ? [["uv", root.readout(WeatherState.vital("uv"))]] : [], root.show_vitals && WeatherState.aqi_now >= 0 ? [["aqi", root.readout(WeatherState.vital("aqi"))]] : [])

    spacing: 4

    FontMetrics {
        id: text_metrics
        font.family: Style.font_family
        font.pixelSize: root.text_px
    }

    Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        textFormat: Text.StyledText
        text: WttrArt.runs([["$ ", Theme.theme_secondary], ["curl wttr.in" + (WeatherState.location_name !== "" ? "/" + WeatherState.location_name.split(",")[0].replace(/ /g, "+") : ""), Theme.fg_core]])
        font.family: Style.font_family
        font.pixelSize: root.text_px
    }

    Text {
        visible: WeatherState.location_name !== ""
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: "Weather report: " + WeatherState.location_name
        color: Style.text_fg
        font.family: Style.font_family
        font.pixelSize: root.text_px
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 12

        Text {
            id: art_text
            Layout.alignment: Qt.AlignTop
            textFormat: Text.StyledText
            text: WttrArt.markup(root.art, root.art_colors)
            color: Style.text_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
            spacing: 0

            Text {
                Layout.fillWidth: true
                wrapMode: root.has ? Text.NoWrap : Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: WeatherState.cond_text(true)
                color: root.has || WeatherState.loading ? Style.text_strong : Theme.warning
                font.family: Style.font_family
                font.pixelSize: root.text_px
            }

            Repeater {
                model: root.rows

                RowLayout {
                    id: kv
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        visible: root.keyed
                        Layout.preferredWidth: root.key_px
                        text: kv.modelData[0]
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: root.text_px
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: kv.modelData[1]
                        color: Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: root.text_px
                    }
                }
            }
        }
    }

    Text {
        visible: WeatherState.stale
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: "warning: stale data" + (WeatherState.error ? " (" + WeatherState.error + ")" : "")
        color: Theme.warning
        font.family: Style.font_family
        font.pixelSize: root.text_px - 1
    }
}
