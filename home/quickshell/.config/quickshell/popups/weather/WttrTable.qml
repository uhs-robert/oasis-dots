// home/quickshell/.config/quickshell/popups/weather/WttrTable.qml
import QtQuick
import "../../theme"
import "../../services"
import "WttrArt.js" as WttrArt

// The Daily window as a box-drawn terminal table: one column per day, the selected column inverted.
Item {
    id: root

    property var days: []
    property int first_day: 0
    property int day_cursor: 0
    property real scale_min: 0
    property real scale_max: 1
    property var on_select: function (i) {}

    readonly property int text_px: Style.font_size - 4
    // Reading metrics.font makes the advance rebind once the family and size land.
    readonly property real glyph_w: metrics.font.pixelSize > 0 ? Math.max(1, metrics.advanceWidth("─")) : 1
    readonly property real lh: Math.max(1, Math.floor(metrics.height))
    readonly property int n: Math.max(1, root.days.length)
    // Cell width in characters, between the column rules.
    readonly property int k: Math.max(3, Math.floor((Math.floor(root.width / root.glyph_w) - 1) / root.n) - 1)
    readonly property int line_chars: (root.k + 1) * root.n + 1
    readonly property real cw: Math.max(root.glyph_w, root.width / root.line_chars)
    readonly property int bar_rows: Math.max(4, Math.floor(root.height / root.lh) - 10)
    readonly property var arrows: ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]
    readonly property int bar_w: root.k >= 7 ? 3 : 1
    readonly property int sel: root.day_cursor - root.first_day
    readonly property color rule: Style.text_muted
    readonly property color inverse: Style.tab_active_fg
    readonly property var art_colors: ({ y: Theme.yellow, c: Qt.tint(Theme.fg_core, Qt.alpha(Theme.fg_dim, 0.55)), d: Theme.fg_dim, r: Theme.blue, s: Theme.fg_strong, t: Theme.bright_yellow, f: Theme.fg_dim, u: Theme.fg_muted })

    function pad(s) {
        const room = Math.max(0, root.k - s.length);
        const left = Math.floor(room / 2);
        return [" ".repeat(left), " ".repeat(room - left)];
    }

    // One cell's runs, centred in k characters.
    function cell(list, i) {
        const text = list.map(r => r[0]).join("").slice(0, root.k);
        const p = root.pad(text);
        let left = root.k;
        const clipped = list.map(r => {
            const t = r[0].slice(0, Math.max(0, left));
            left -= t.length;
            return [t, r[1]];
        });
        const body = i === root.sel ? [[text, String(root.inverse)]] : clipped;
        return [[p[0], ""]].concat(body, [[p[1], ""]]);
    }

    function row(make) {
        let out = [["│", String(root.rule)]];
        for (let i = 0; i < root.days.length; i++) out = out.concat(root.cell(make(root.days[i], i), i), [["│", String(root.rule)]]);
        return WttrArt.runs(out);
    }

    function border(l, m, r) {
        const seg = "─".repeat(root.k);
        return WttrArt.runs([[l + Array(root.days.length).fill(seg).join(m) + r, String(root.rule)]]);
    }

    function mini(day, line) {
        const art = WttrArt.minis[WttrArt.kind(day.code)];
        return WttrArt.line_runs(art, line, root.art_colors);
    }

    // Bar row r (0 at the top) of the day's range in half blocks, labelled just above and below.
    function bar(day, r) {
        const inner = root.bar_rows - 2;
        const step = (root.scale_max - root.scale_min) / inner;
        const row_of = t => 1 + Math.min(inner - 1, Math.max(0, Math.floor((root.scale_max - t) / step)));
        if (r === row_of(day.max) - 1) return [[Math.round(day.max) + "°", String(WeatherState.temp_color(day.max))]];
        if (r === row_of(day.min) + 1) return [[Math.round(day.min) + "°", String(WeatherState.temp_color(day.min))]];
        if (r < 1 || r > inner) return [["", ""]];
        const top = root.scale_max - (r - 1) * step;
        const hit = (hi, lo) => day.max >= lo && day.min <= hi;
        const up = hit(top, top - step / 2);
        const down = hit(top - step / 2, top - step);
        const ch = up && down ? "█" : up ? "▀" : down ? "▄" : " ";
        return [[ch.repeat(root.bar_w), String(WeatherState.temp_color(top - step / 2))]];
    }

    readonly property var lines: {
        if (root.days.length === 0) return [];
        const out = [
            root.border("┌", "┬", "┐"),
            root.row(d => [[d.weekday, String(Style.text_strong)]]),
            root.border("├", "┼", "┤"),
            root.row(d => root.mini(d, 0)),
            root.row(d => root.mini(d, 1))
        ];
        for (let r = 0; r < root.bar_rows; r++) out.push(root.row(d => root.bar(d, r)));
        out.push(root.border("├", "┼", "┤"));
        out.push(root.row(d => [[d.pop + "%", String(d.pop > 0 ? Theme.blue : Style.text_muted)]]));
        out.push(root.row(d => [[root.arrows[Math.round(((d.wind_dir % 360) + 360) % 360 / 45) % 8] + " ", String(Style.text_strong)], [String(Math.round(d.wind_speed_max)), String(Style.text_fg)]]));
        out.push(root.border("└", "┴", "┘"));
        return out;
    }

    FontMetrics {
        id: metrics
        font.family: Style.font_family
        font.pixelSize: root.text_px
    }

    Rectangle {
        visible: root.sel >= 0 && root.sel < root.days.length
        x: (1 + root.sel * (root.k + 1)) * root.cw
        y: root.lh
        width: root.k * root.cw
        height: root.lh * (root.lines.length - 2)
        color: Style.tab_active_bg
    }

    Column {
        Repeater {
            model: root.lines.length

            Text {
                required property int index
                height: root.lh
                textFormat: Text.StyledText
                text: root.lines[index] ?? ""
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: root.text_px
                transform: Scale {
                    xScale: root.cw / root.glyph_w
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: mouse => {
            const i = Math.floor(mouse.x / root.cw / (root.k + 1));
            if (i >= 0 && i < root.days.length) root.on_select(root.first_day + i);
        }
    }
}
