// home/quickshell/.config/quickshell/bar/modules/Battery.qml
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../theme"
import "../../services"
import "../../components"

BarModule {
    id: root
    module_name: "battery"

    WheelStepper {
        id: wheel_stepper
    }

    readonly property var device: UPower.displayDevice
    readonly property bool has_battery: !!device && device.ready && device.isLaptopBattery
    readonly property real percent: has_battery ? device.percentage * 100 : 0
    readonly property int power_state: has_battery ? device.state : UPowerDeviceState.Unknown
    readonly property bool charging: power_state === UPowerDeviceState.Charging || power_state === UPowerDeviceState.PendingCharge
    readonly property var level_glyphs: ["", "", "", "", ""]

    shown: has_battery && Math.round(percent) < 100 && power_state !== UPowerDeviceState.FullyCharged
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    readonly property string glyph: {
        if (power_state === UPowerDeviceState.FullyCharged) return "󱟢";
        if (charging) return "";
        if (percent <= 20) return level_glyphs[0];
        if (percent <= 40) return level_glyphs[1];
        if (percent <= 60) return level_glyphs[2];
        if (percent <= 80) return level_glyphs[3];
        return level_glyphs[4];
    }

    readonly property color glyph_color: {
        if (charging || power_state === UPowerDeviceState.FullyCharged) return Theme.theme_primary;
        if (percent <= 20) return Theme.theme_label;
        if (percent <= 50) return Theme.warning;
        return Theme.theme_primary;
    }

    function format_time(seconds) {
        if (seconds <= 0) return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.round((seconds % 3600) / 60);
        return h > 0 ? (h + "h " + m + "m") : (m + "m");
    }

    tooltip_text: {
        if (!has_battery) return "";
        if (device.timeToEmpty > 0) return format_time(device.timeToEmpty) + " remaining";
        if (device.timeToFull > 0) return format_time(device.timeToFull) + " until full";
        return Math.round(percent) + "%";
    }

    RowLayout {
        id: row
        spacing: 6

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.glyph
            color: root.glyph_color
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_glyph_size
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: Math.round(root.percent) + "%"
            color: Style.bar_fg
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size
            font.capitalization: Style.bar_capitalization
            font.letterSpacing: Style.bar_letter_spacing
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggle_popup()
        onWheel: wheel => {
            const notches = wheel_stepper.consume(wheel.angleDelta.y || wheel.pixelDelta.y);
            if (notches === 0) return;
            Backlight.set_percent(wheel_stepper.snap_by(Backlight.percent, notches, 1, 100));
        }
    }
}
