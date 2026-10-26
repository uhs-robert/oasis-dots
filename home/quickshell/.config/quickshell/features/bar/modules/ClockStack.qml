import QtQuick
import qs.theme
import qs.ui.effects
import qs.features.clock
import qs.features.clock.markers as Marker
import qs.styles.modern.widgets as Modern
import "../VerticalLayout.js" as VerticalLayout

// The bar clock on a side bar: hours over minutes, upright, with the style's chip or capsule around them,
// the nes sun or moon above and the meeting marker below. Seconds, zone and date are not drawn here (the date is in the clock's tooltip).
Column {
    id: root

    // The shown time, already in the shown zone.
    property date shifted: new Date()
    // The width the clock may use, from the Clock module.
    property real cross: 0
    property bool chip: false
    property bool capsule: false
    property bool lualine: false
    property bool on_accent: false
    property color ink: "black"
    // The nes sun or moon: its pixel rows and colours come from Clock, which picks day or night.
    property bool sprite_shown: false
    property var sprite_rows: []
    property var sprite_colors: []
    property font marker_font

    readonly property var lines: VerticalLayout.clock_lines(root.shifted.getHours(), root.shifted.getMinutes(), TimeFormat.h24)
    readonly property real chip_pad: 3
    readonly property real text_avail: root.chip ? root.cross - root.chip_pad * 2 : root.cross
    readonly property int base_size: root.lualine ? Style.bar_clock_size || Style.bar_glyph_size : root.chip ? Style.bar_font_size + 2 : Style.bar_font_size
    readonly property string family: root.chip ? Style.bar_clock_font : Style.bar_font_family
    readonly property real spacing_px: root.chip ? 0 : Style.bar_letter_spacing
    // Fitted from "00", the widest pair, so the size does not change as the digits do.
    readonly property int fit_px: VerticalLayout.fit_size({ glyph_per_px: probe.advanceWidth / root.base_size, fixed: 2 * root.spacing_px }, root.text_avail, root.base_size, VerticalLayout.min_text_px)
    // The capsule draws its time in a bolder, 3 px larger face than the plain text.
    readonly property int capsule_fit_px: VerticalLayout.fit_size({ glyph_per_px: capsule_probe.advanceWidth / capsule_probe.font.pixelSize, fixed: 0 }, root.cross, Style.bar_font_size + 3, VerticalLayout.min_text_px)
    readonly property color text_color: root.on_accent ? root.ink : root.chip || root.lualine ? Style.bar_clock_fg : Style.bar_fg

    spacing: 3

    TextMetrics {
        id: probe
        text: "00"
        font.family: root.family
        font.pixelSize: root.base_size
        font.features: { "tnum": 1 }
        font.capitalization: Style.bar_capitalization
    }

    TextMetrics {
        id: capsule_probe
        text: "00"
        font.family: Style.bar_clock_font
        font.pixelSize: Style.bar_font_size + 3
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }

    PixelSprite {
        visible: root.sprite_shown
        anchors.horizontalCenter: parent.horizontalCenter
        pixel: 1
        colors: root.sprite_colors
        rows: root.sprite_rows
    }

    Loader {
        active: root.capsule
        visible: active
        anchors.horizontalCenter: parent.horizontalCenter
        sourceComponent: Modern.CapsuleClock {
            vertical: true
            line_px: root.capsule_fit_px
            lines: root.lines
        }
    }

    Rectangle {
        visible: !root.capsule
        anchors.horizontalCenter: parent.horizontalCenter
        width: digits.width + (root.chip ? root.chip_pad * 2 : 0)
        height: digits.height + (root.chip ? root.chip_pad * 2 : 0)
        radius: 3
        color: root.chip ? Style.bar_clock_bg : "transparent"

        Column {
            id: digits
            anchors.centerIn: parent

            Repeater {
                model: root.lines

                Text {
                    required property string modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData
                    color: root.text_color
                    font.family: root.family
                    font.features: { "tnum": 1 }
                    font.pixelSize: root.fit_px
                    font.capitalization: Style.bar_capitalization
                    font.letterSpacing: root.spacing_px
                    style: root.chip ? Text.Normal : Style.bar_text_style
                    styleColor: Style.bar_glow_color
                    // Held to the width of "00" so a narrow pair ("11") does not shift the chip.
                    width: Math.ceil(probe.advanceWidth * root.fit_px / root.base_size)
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    // A marker wider than the bar is scaled down to it rather than cut off.
    Item {
        visible: marker.visible
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property real fit: marker.width > 0 ? Math.min(1, root.cross / marker.width) : 1
        width: marker.width * fit
        height: marker.height * fit

        Marker.MeetingMarker {
            id: marker
            visible: CalendarState.in_meeting || CalendarState.chip_event !== null
            transformOrigin: Item.TopLeft
            scale: parent.fit
            readonly property bool chip_shown: CalendarState.chip_event !== null
            minutes: marker.chip_shown ? CalendarState.minutes_to(CalendarState.chip_event) : 0
            in_meeting: CalendarState.in_meeting
            upcoming: marker.chip_shown
            progress: marker.chip_shown ? Math.max(0, Math.min(1, 1 - marker.minutes / CalendarState.chip_window_minutes)) : 1
            on_accent: root.on_accent
            ink: root.ink
            text_font: root.marker_font
        }
    }
}
