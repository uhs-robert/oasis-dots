// home/quickshell/.config/quickshell/popups/weather/LspDayColumn.qml
import QtQuick
import "../../theme"
import "../../services"

// One day as a Neovim buffer: the day as a tab name, a syntax-coloured Nerd Font condition glyph, the range as a
// block-character bar with lo/hi inlay hints, and the rain chance as diagnostic virtual text; the selected day is the cursor line.
Item {
    id: root

    property var day: null
    property int day_index: 0
    property string label: ""
    property bool selected: false
    property real col_w: 0
    // The week's coldest low and warmest high, shared by every column so ranges compare across days.
    property real scale_min: 0
    property real scale_max: 1

    readonly property var condition_glyphs: ({
        clear: "\u{f0599}",
        partly_cloudy: "\u{f0595}",
        overcast: "\u{f0590}",
        fog: "\u{f0591}",
        drizzle: "\u{f0f33}",
        rain: "\u{f0597}",
        heavy_rain: "\u{f0596}",
        freezing_rain: "\u{f067f}",
        snow: "\u{f0598}",
        heavy_snow: "\u{f0f36}",
        thunderstorm: "\u{f067e}"
    })
    // Conditions coloured like highlight groups: sun as a string literal, rain as a function, storms as a keyword.
    readonly property var condition_colors: ({
        clear: Style.pal.yellow,
        partly_cloudy: Style.pal.bright_yellow,
        overcast: Style.pal.fg_dim,
        fog: Style.pal.fg_muted,
        drizzle: Style.pal.bright_blue,
        rain: Style.pal.blue,
        heavy_rain: Style.pal.blue,
        freezing_rain: Style.pal.bright_cyan,
        snow: Style.pal.cyan,
        heavy_snow: Style.pal.bright_cyan,
        thunderstorm: Style.pal.magenta
    })
    readonly property string condition: root.day ? WeatherState.weather_color_keys[Math.round(root.day.code)] || "clear" : "clear"
    readonly property var lower_eighths: ["", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    readonly property int sign_w: Math.min(10, Math.round(root.width * 0.14))
    readonly property real track_top: tab.height + icon.height + 10 + hint_metrics.height + 4
    readonly property real track_bottom: root.height - rain.height - 8 - hint_metrics.height - 4
    readonly property int cell_h: Math.max(1, Math.ceil(cell_metrics.height))
    readonly property int cells: Math.max(1, Math.floor((root.track_bottom - root.track_top) / root.cell_h))
    readonly property real track_base: root.track_top + root.cells * root.cell_h

    function frac(t) {
        return Math.max(0, Math.min(1, (t - root.scale_min) / Math.max(0.01, root.scale_max - root.scale_min)));
    }

    // The low snaps to a whole cell because only lower-eighth blocks exist; the high keeps eighth precision.
    readonly property int lo_cell: root.day ? Math.min(root.cells - 1, Math.floor(root.frac(root.day.min) * root.cells)) : 0
    readonly property int hi_eighth: root.day ? Math.max(root.lo_cell * 8 + 1, Math.round(root.frac(root.day.max) * root.cells * 8)) : 1
    readonly property int bar_cells: Math.ceil(root.hi_eighth / 8) - root.lo_cell

    FontMetrics {
        id: cell_metrics
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-2)
    }

    FontMetrics {
        id: hint_metrics
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-4)
    }

    Rectangle {
        id: tab
        width: parent.width
        height: tab_text.implicitHeight + 6
        color: root.selected ? Style.pal.visual_bg : Style.tab_bg

        Rectangle {
            visible: root.selected
            width: 2
            height: parent.height
            color: Style.tab_marker
        }

        Text {
            id: tab_text
            anchors.centerIn: parent
            width: parent.width - 6
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.label
            color: root.selected ? Style.text_strong : Style.tab_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
            font.bold: root.selected
            font.italic: !root.selected
        }
    }

    Rectangle {
        visible: root.selected
        y: tab.height
        width: parent.width
        height: parent.height - tab.height
        color: Style.selection_bg
    }

    Text {
        visible: root.selected
        width: root.sign_w
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: icon.verticalCenter
        text: "▎"
        color: Style.caret_color
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-1)
    }

    Text {
        id: icon
        x: root.sign_w + (root.width - root.sign_w * 2 - width) / 2
        y: tab.height + 8
        text: root.condition_glyphs[root.condition]
        color: root.condition_colors[root.condition]
        opacity: root.selected ? 1 : 0.8
        font.family: Style.font_family
        font.pixelSize: Math.max(16, Math.min(30, root.width * 0.42))
    }

    // An indent guide the full height of the week's scale, so a short day still shows where it sits.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.track_top
        width: 1
        height: root.track_base - root.track_top
        color: Qt.alpha(Style.text_muted, root.selected ? 0.5 : 0.3)
    }

    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: cell_metrics.advanceWidth("█")
        height: parent.height

        Repeater {
            model: root.day ? root.bar_cells : 0

            Text {
                id: cell
                required property int index
                readonly property int cell_index: root.lo_cell + cell.index
                y: root.track_base - (cell.cell_index + 1) * root.cell_h
                height: root.cell_h
                verticalAlignment: Text.AlignBottom
                text: root.lower_eighths[Math.min(8, root.hi_eighth - cell.cell_index * 8)]
                color: WeatherState.temp_color(root.scale_min + (cell.cell_index + 0.5) / root.cells * (root.scale_max - root.scale_min))
                opacity: root.selected ? 1 : 0.75
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-2)
            }
        }
    }

    InlayHint {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.track_base - root.hi_eighth / 8 * root.cell_h - height - 3
        text: root.day ? Math.round(root.day.max) + "°" : ""
    }

    InlayHint {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.track_base - root.lo_cell * root.cell_h + 3
        text: root.day ? Math.round(root.day.min) + "°" : ""
    }

    Rectangle {
        id: rain
        readonly property bool wet: !!root.day && root.day.pop > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        width: Math.min(root.width - 2, rain_text.implicitWidth + 8)
        height: rain_text.implicitHeight + 2
        radius: 3
        color: rain.wet ? Qt.alpha(Style.pal.info, 0.13) : "transparent"

        Text {
            id: rain_text
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 4)
            elide: Text.ElideRight
            text: "\u{f0597} " + (root.day ? root.day.pop : 0) + "%"
            color: rain.wet ? Style.pal.info : Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
        }
    }

    component InlayHint: Rectangle {
        property alias text: hint_text.text

        width: hint_text.implicitWidth + 6
        height: hint_text.implicitHeight
        radius: 2
        color: Qt.alpha(Style.text_dim, root.selected ? 0.18 : 0.1)

        Text {
            id: hint_text
            anchors.centerIn: parent
            color: root.selected ? Style.text_fg : Style.text_dim
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-4)
        }
    }
}
