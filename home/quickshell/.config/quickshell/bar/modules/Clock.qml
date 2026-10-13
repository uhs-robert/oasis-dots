// home/quickshell/.config/quickshell/bar/modules/Clock.qml
import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "../../components"
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

    // The next meeting is worth the bar's room only just before it starts; a meeting under way shows as a dot.
    readonly property bool chip_shown: CalendarState.minutes_until_next > 0 && CalendarState.minutes_until_next <= CalendarState.chip_window_minutes
    // The title is cut, not the minutes, so the countdown always shows.
    readonly property string chip_text: {
        const title = CalendarState.next_event_today ? CalendarState.next_event_today.title : "";
        return (root.compact ? "" : (title.length > 18 ? title.slice(0, 17) + "\u2026" : title) + " ") + CalendarState.minutes_until_next + "m";
    }
    readonly property string agenda_tip: {
        const span = e => TimeFormat.format(new Date(e.start_ms)) + " - " + TimeFormat.format(new Date(e.end_ms));
        if (CalendarState.in_meeting) return "Now: " + CalendarState.current_event.title + "\n" + span(CalendarState.current_event);
        const next = CalendarState.next_event_today;
        return next ? "Next: " + next.title + "\n" + span(next) + " (in " + CalendarState.minutes_until_next + " min)" : "";
    }
    onAgenda_tipChanged: if (hover.hovered && root.agenda_tip !== "") Tooltip.show(root, root.agenda_tip, "calendar")

    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered && root.agenda_tip !== "") Tooltip.show(root, root.agenda_tip, "calendar");
            else Tooltip.hide(root);
        }
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

    readonly property string date_text: Qt.formatDateTime(root.shifted, "ddd MMM dd")

    // nes: a Dragon Quest window holding a pixel sun or moon, the time, and the date in the secondary colour.
    readonly property bool dq: Style.console_views === "nes" && !root.capsule

    function minute_of(hhmm) {
        const m = /^(\d{1,2}):(\d{2})/.exec(hhmm || "");
        return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
    }

    // Sunrise and sunset are in the weather location's clock, so its minute is taken there; without weather, day is 06:00 to 18:00 in the shown zone.
    readonly property bool daytime: {
        if (!root.dq) return true;
        const rise = root.minute_of(WeatherState.sunrise);
        const set = root.minute_of(WeatherState.sunset);
        if (WeatherState.has_data && rise >= 0 && set > rise) {
            const there = new Date(clock.date.getTime() + WeatherState.utc_offset * 1000);
            const now = there.getUTCHours() * 60 + there.getUTCMinutes();
            return now >= rise && now < set;
        }
        const now = root.shifted.getHours() * 60 + root.shifted.getMinutes();
        return now >= 360 && now < 1080;
    }

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

    PixelSprite {
        visible: root.dq
        anchors.verticalCenter: parent.verticalCenter
        pixel: 1
        colors: [Theme.theme_secondary_strong, Theme.theme_secondary]
        rows: root.daytime ? [".....11.....", ".1...11...1.", "..1......1..", "....0000....", "...011110...", "11.011110.11", "11.011110.11", "...011110...", "....0000....", "..1......1..", ".1...11...1.", ".....11....."] : ["....0000....", "..00111100..", ".0111110000.", ".0111100....", "011110......", "011110......", "011110......", "011110......", ".0111100....", ".0111110000.", "..00111100..", "....0000...."]
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
        visible: !root.compact && !root.capsule && !root.on_accent && !root.dq && Style.bar_separator === ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.lualine ? "\u00b7" : "|"
        color: root.on_accent ? Qt.alpha(root.ink, 0.6) : root.lualine || root.horizon ? Style.text_muted : Theme.theme_primary
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: Style.bar_font_size
        font.capitalization: Style.bar_capitalization
        font.letterSpacing: Style.bar_letter_spacing
    }

    Text {
        visible: !root.compact && !root.capsule && !root.on_accent && !root.dq
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

    Text {
        visible: root.dq && !root.compact
        anchors.verticalCenter: parent.verticalCenter
        text: "  " + Qt.formatDateTime(root.shifted, "MMM d").toUpperCase()
        color: Theme.theme_secondary
        font: time_label.font
    }

    Rectangle {
        visible: CalendarState.in_meeting
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 6
        radius: 3
        color: root.on_accent ? root.ink : Theme.theme_primary
    }

    Text {
        visible: root.chip_shown
        anchors.verticalCenter: parent.verticalCenter
        text: root.chip_text
        color: root.on_accent ? root.ink : Theme.theme_primary
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: Style.bar_font_size
        font.capitalization: Style.bar_capitalization
        font.letterSpacing: Style.bar_letter_spacing
    }
}
