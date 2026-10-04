// home/quickshell/.config/quickshell/bar/modules/Clock.qml
import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "../../components/modern" as Modern

Row {
    id: root

    property bool compact: false
    property string screen_name: ""
    property int bar_height: 30
    property Item island: null
    property color island_color: "transparent"
    // Set by a lualine section with a strong fill (lualine_z); the clock then opens its own popup.
    property bool on_accent: false
    readonly property color ink: Theme.bg_crust
    // Set by the bar when its oasis horizon art sits behind this clock; it needs room for the palm and sky.
    property bool horizon: false
    readonly property date date: clock.date
    spacing: 6
    leftPadding: root.horizon ? 24 : 0
    rightPadding: root.horizon ? 22 : 0
    transform: Translate { y: root.horizon ? -4 : 0 }

    TapHandler {
        enabled: root.on_accent && !!root.island
        onTapped: Popups.toggle("clock", root.island, root.island_color, root.screen_name)
    }

    SystemClock {
        id: clock
        precision: root.show_seconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // Seconds tick once a second, so they are dropped on battery.
    readonly property bool show_seconds: !root.compact && Power.on_ac
    readonly property var shifted: Timezones.shift(clock.date)

    // Styles with a clock chip draw the digits on it and the zone beside it.
    readonly property bool chip: Style.bar_clock_bg.a > 0
    readonly property bool capsule: Style.bar_clock_layout === "capsule"
    // Lualine: bold digits, the zone and date dimmed after them.
    readonly property bool lualine: Style.bar_lualine
    readonly property string digits_text: TimeFormat.digits(root.shifted, root.show_seconds)
    readonly property string zone_text: root.compact ? "" : Timezones.is_local ? Qt.formatDateTime(root.shifted, "t") : Timezones.abbrev
    readonly property string time_text: root.zone_text === "" ? root.digits_text : root.digits_text + " " + root.zone_text

    // A Mario HUD line: TIME and WORLD captions, the date as month-day.
    readonly property bool hud: Style.console_views === "nes"
    readonly property string date_text: root.hud ? Qt.formatDateTime(root.shifted, "M-d") : Qt.formatDateTime(root.shifted, "ddd MMM dd")

    // Proportional fonts would resize the island every tick; tabular digits and a width floor hold it still.
    TextMetrics {
        id: time_metrics
        text: (root.capsule ? root.digits_text : time_label.text).replace(/\d/g, "0")
        font: root.capsule && capsule_loader.item ? capsule_loader.item.time_font : time_label.font
    }

    Loader {
        id: capsule_loader
        active: root.capsule
        visible: active
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: Modern.CapsuleClock {
            time_text: root.digits_text
            zone_text: root.zone_text
            date_text: root.date_text
            compact: root.compact
            time_floor: time_metrics.advanceWidth
        }
    }

    Text {
        visible: Style.bar_clock_brackets.a > 0 && !root.capsule
        anchors.verticalCenter: parent.verticalCenter
        text: "["
        color: Style.bar_clock_brackets
        font: time_label.font
    }

    Text {
        visible: root.lualine
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{f0954}"
        color: root.on_accent ? root.ink : Theme.theme_primary
        font.family: Style.bar_font_family
        font.pixelSize: Style.bar_clock_size || Style.bar_glyph_size
    }

    Text {
        visible: root.hud && !root.capsule
        anchors.verticalCenter: parent.verticalCenter
        text: "TIME"
        color: Theme.theme_primary
        font.family: Style.bar_font_family
        font.pixelSize: Style.bar_font_size
    }

    Rectangle {
        visible: !root.capsule
        readonly property real pad: root.chip ? 5 : 0
        anchors.verticalCenter: parent.verticalCenter
        width: time_label.width + pad * 2
        height: time_label.height + pad
        radius: 3
        color: root.chip ? Style.bar_clock_bg : "transparent"

        Text {
            id: time_label
            x: parent.pad
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(implicitWidth, Math.ceil(time_metrics.advanceWidth))
            text: root.on_accent ? (TimeFormat.h24 ? root.digits_text : root.digits_text + " " + TimeFormat.meridiem(root.shifted)) : root.chip || root.lualine ? root.digits_text : root.time_text
            color: root.on_accent ? root.ink : root.chip || root.lualine ? Style.bar_clock_fg : Style.bar_fg
            font.family: root.chip ? Style.bar_clock_font : Style.bar_font_family
            font.features: { "tnum": 1 }
            font.weight: root.horizon ? Font.DemiBold : Font.Normal
            style: root.chip ? Text.Normal : Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: root.lualine ? Style.bar_clock_size || Style.bar_glyph_size : root.chip ? Style.bar_font_size + 2 : Style.bar_font_size
            font.capitalization: Style.bar_capitalization
            font.letterSpacing: root.chip ? 0 : Style.bar_letter_spacing
        }
    }

    Text {
        visible: (root.chip || root.lualine) && root.zone_text !== "" && !root.capsule && !root.on_accent
        anchors.verticalCenter: parent.verticalCenter
        text: root.zone_text
        color: root.lualine ? Style.text_dim : Style.bar_fg
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: Style.bar_font_size
        font.capitalization: Style.bar_capitalization
        font.letterSpacing: Style.bar_letter_spacing
    }

    Rectangle {
        visible: !root.compact && !root.capsule && !root.on_accent && Style.bar_separator === "tick"
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: Style.bar_font_size + 2
        color: Style.bar_tick_color
    }

    Text {
        visible: !root.compact && !root.capsule && !root.on_accent && Style.bar_separator === ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.hud ? " WORLD" : root.lualine ? "\u00b7" : "|"
        color: root.on_accent ? Qt.alpha(root.ink, 0.6) : root.lualine || root.horizon ? Style.text_muted : Theme.theme_primary
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: Style.bar_font_size
        font.capitalization: Style.bar_capitalization
        font.letterSpacing: Style.bar_letter_spacing
    }

    Text {
        visible: !root.compact && !root.capsule && !root.on_accent
        anchors.verticalCenter: parent.verticalCenter
        text: root.date_text
        color: root.on_accent ? Qt.alpha(root.ink, 0.75) : root.lualine || root.horizon ? Style.text_dim : Style.bar_fg
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: root.horizon ? Style.bar_font_size - 2 : Style.bar_font_size
        font.capitalization: Style.bar_capitalization
        font.letterSpacing: Style.bar_letter_spacing
    }

    Text {
        visible: Style.bar_clock_brackets.a > 0 && !root.capsule
        anchors.verticalCenter: parent.verticalCenter
        text: "]"
        color: Style.bar_clock_brackets
        font: time_label.font
    }
}
