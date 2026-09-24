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

    readonly property string time_text: {
        const d = Timezones.shift(clock.date);
        const h = pad2(d.getHours() % 12 || 12);
        const m = pad2(d.getMinutes());
        if (root.compact) return h + ":" + m;
        return h + ":" + m + ":" + pad2(d.getSeconds()) + " " + (Timezones.is_local ? Qt.formatDateTime(d, "t") : Timezones.abbrev);
    }

    readonly property string date_text: Qt.formatDateTime(Timezones.shift(clock.date), "ddd MMM dd")

    // Proportional fonts would resize the island every tick; tabular digits and a width floor hold it still.
    TextMetrics {
        id: time_metrics
        text: root.time_text.replace(/\d/g, "0")
        font: time_label.font
    }

    Text {
        id: time_label
        width: Math.max(implicitWidth, Math.ceil(time_metrics.advanceWidth))
        text: root.time_text
        color: Style.bar_fg
        font.family: Style.bar_font_family
        font.features: { "tnum": 1 }
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: Style.bar_font_size
    }

    Text {
        visible: !root.compact
        text: "|"
        color: Theme.theme_primary
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: Style.bar_font_size
    }

    Text {
        visible: !root.compact
        text: root.date_text
        color: Style.bar_fg
        font.family: Style.bar_font_family
        style: Style.bar_text_style
        styleColor: Style.bar_glow_color
        font.pixelSize: Style.bar_font_size
    }
}
