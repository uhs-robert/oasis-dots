// home/quickshell/.config/quickshell/bar/modules/Battery.qml
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../theme"
import "../../services"
import "../../components"

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property Item island: null
    property color island_color: Theme.bg_core

    WheelStepper {
        id: wheel_stepper
    }

    readonly property var device: UPower.displayDevice
    readonly property bool has_battery: !!device && device.ready && device.isLaptopBattery
    readonly property real percent: has_battery ? device.percentage * 100 : 0
    readonly property int state: has_battery ? device.state : UPowerDeviceState.Unknown
    readonly property bool charging: state === UPowerDeviceState.Charging || state === UPowerDeviceState.PendingCharge
    readonly property var level_glyphs: ["", "", "", "", ""]

    readonly property bool shown: has_battery && Math.round(percent) < 100 && state !== UPowerDeviceState.FullyCharged
    visible: shown
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    readonly property string glyph: {
        if (state === UPowerDeviceState.FullyCharged) return "󱟢";
        if (charging) return "";
        if (percent <= 20) return level_glyphs[0];
        if (percent <= 40) return level_glyphs[1];
        if (percent <= 60) return level_glyphs[2];
        if (percent <= 80) return level_glyphs[3];
        return level_glyphs[4];
    }

    readonly property color glyph_color: {
        if (charging || state === UPowerDeviceState.FullyCharged) return Theme.theme_primary;
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

    readonly property string tooltip_text: {
        if (!has_battery) return "";
        if (device.timeToEmpty > 0) return format_time(device.timeToEmpty) + " remaining";
        if (device.timeToFull > 0) return format_time(device.timeToFull) + " until full";
        return Math.round(percent) + "%";
    }

    onIslandChanged: if (root.island) Popups.register_default("battery", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("battery", root.screen_name, root)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        opacity: hover_handler.hovered ? 0.5 : 0
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
            font.pixelSize: Theme.glyph_size
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: Math.round(root.percent) + "%"
            color: Style.bar_fg
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text);
            else Tooltip.hide();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Popups.toggle("battery", root.island, root.island_color, root.screen_name)
        onWheel: wheel => {
            const notches = wheel_stepper.consume(wheel.angleDelta.y || wheel.pixelDelta.y);
            if (notches === 0) return;
            Backlight.set_percent(wheel_stepper.snap_by(Backlight.percent, notches, 1, 100));
        }
    }
}
