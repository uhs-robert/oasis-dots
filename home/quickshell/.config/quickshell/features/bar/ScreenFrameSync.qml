import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.theme
import "Corners.js" as Corners

// Tells Hyprland the screen frame's corner radius, so window rounding follows it (ScreenFrame.set_rounding in
// config/general/frame.lua, which keeps the user's rounding and restores it for -1 or when the frame layer goes).
Scope {
    id: root

    // Only a round corner has curved windows to match; the other profiles send 0 so windows stay square (0 is a radius,
    // -1 the "frame is off" that restores the user's rounding).
    readonly property int wanted_radius: Style.screen_frame_on ? Corners.window_rounding(Style.screen_frame_profile.corner, Style.screen_frame_profile.radius) : -1

    function send() {
        Hyprland.dispatch("ScreenFrame.set_rounding(" + root.wanted_radius + ")");
    }

    // The style picker previews frames as it moves, so only the radius it settles on reaches Hyprland.
    onWanted_radiusChanged: debounce.restart()

    Timer {
        id: debounce
        interval: 150
        onTriggered: root.send()
    }

    // A Hyprland reload rebuilds the config with the user's rounding and forgets the saved one. No teardown on
    // destruction: a Quickshell reload would land it after the new generation's send, and frame.lua's watchdog
    // restores the rounding after a quit.
    Component.onCompleted: root.send()

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded") root.send();
        }
    }
}
