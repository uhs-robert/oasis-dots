// home/quickshell/.config/quickshell/bar/modules/Clock.qml
import QtQuick
import Quickshell
import "../../theme"
import "../../services"

Row {
    id: root

    property bool compact: false
    spacing: 6

    SystemClock {
        id: clock
        precision: root.compact ? SystemClock.Minutes : SystemClock.Seconds
    }

    function pad2(n) {
        return n < 10 ? "0" + n : "" + n;
    }

    // Styles with a clock chip draw the digits on it and the zone beside it.
    readonly property bool chip: Style.bar_clock_bg.a > 0
    readonly property string digits_text: {
        const d = Timezones.shift(clock.date);
        const hm = pad2(d.getHours() % 12 || 12) + ":" + pad2(d.getMinutes());
        return root.compact ? hm : hm + ":" + pad2(d.getSeconds());
    }
    readonly property string zone_text: root.compact ? "" : Timezones.is_local ? Qt.formatDateTime(Timezones.shift(clock.date), "t") : Timezones.abbrev
    readonly property string time_text: root.zone_text === "" ? root.digits_text : root.digits_text + " " + root.zone_text

    readonly property string date_text: Qt.formatDateTime(Timezones.shift(clock.date), "ddd MMM dd")

    // Proportional fonts would resize the island every tick; tabular digits and a width floor hold it still.
    TextMetrics {
        id: time_metrics
        text: time_label.text.replace(/\d/g, "0")
        font: time_label.font
    }

    Text {
        visible: Style.bar_clock_brackets.a > 0
        anchors.verticalCenter: parent.verticalCenter
        text: "["
        color: Style.bar_clock_brackets
        font: time_label.font
    }

    Rectangle {
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
            text: root.chip ? root.digits_text : root.time_text
            color: root.chip ? Style.bar_clock_fg : Style.bar_fg
            font.family: root.chip ? Style.bar_clock_font : Style.bar_font_family
            font.features: { "tnum": 1 }
            style: root.chip ? Text.Normal : Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: root.chip ? Style.bar_font_size + 2 : Style.bar_font_size
            font.capitalization: Style.bar_capitalization
            font.letterSpacing: root.chip ? 0 : Style.bar_letter_spacing
        }
    }

    Text {
        visible: root.chip && root.zone_text !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.zone_text
        color: Style.bar_fg
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: Style.bar_font_size
        font.capitalization: Style.bar_capitalization
        font.letterSpacing: Style.bar_letter_spacing
    }

    Text {
        visible: !root.compact
        anchors.verticalCenter: parent.verticalCenter
        text: "|"
        color: Theme.theme_primary
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: Style.bar_font_size
        font.capitalization: Style.bar_capitalization
        font.letterSpacing: Style.bar_letter_spacing
    }

    Text {
        visible: !root.compact
        anchors.verticalCenter: parent.verticalCenter
        text: root.date_text
        color: Style.bar_fg
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: Style.bar_font_size
        font.capitalization: Style.bar_capitalization
        font.letterSpacing: Style.bar_letter_spacing
    }

    Text {
        visible: Style.bar_clock_brackets.a > 0
        anchors.verticalCenter: parent.verticalCenter
        text: "]"
        color: Style.bar_clock_brackets
        font: time_label.font
    }
}
