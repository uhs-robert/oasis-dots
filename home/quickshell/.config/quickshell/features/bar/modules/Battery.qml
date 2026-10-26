import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.theme
import qs.ui
import qs.features.bar
import qs.features.power
import qs.features.display

BarModule {
    id: root
    module_name: "battery"
    hover_popup: true

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

    readonly property string level_variant: {
        if (power_state === UPowerDeviceState.FullyCharged) return "full";
        if (charging) return "charging";
        if (percent <= 20) return "level_0";
        if (percent <= 40) return "level_1";
        if (percent <= 60) return "level_2";
        if (percent <= 80) return "level_3";
        return "level_4";
    }

    readonly property color glyph_color: {
        if (charging || power_state === UPowerDeviceState.FullyCharged) return Theme.theme_primary;
        if (percent <= 20) return Theme.theme_label;
        if (percent <= 50) return Theme.warning;
        return Theme.theme_primary;
    }

    tooltip_text: {
        if (!has_battery) return "";
        if (device.timeToEmpty > 0) return Power.format_time(device.timeToEmpty) + " remaining";
        if (device.timeToFull > 0) return Power.format_time(device.timeToFull) + " until full";
        return Math.round(percent) + "%";
    }

    ModuleRow {
        id: row
        vertical: root.vertical
        spacing: root.vertical ? 2 : 6

        BarIcon {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            ink_centre: root.vertical
            name: "battery"
            fixed_slot: true
            variant: root.level_variant
            glyph: root.glyph
            tint: root.glyph_color
        }

        VerticalText {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            vertical: root.vertical
            cross: root.cross
            full_text: Math.round(root.percent) + "%"
            short_text: Math.round(root.percent) + ""
            full_template: "100%"
            short_template: "100"
            color: Style.bar_fg
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggle_popup()
        onWheel: wheel => {
            const pct = wheel_stepper.step_level(wheel, null, Backlight.percent, 1, 100);
            if (pct !== Backlight.percent) Backlight.set_percent(pct);
        }
    }
}
