import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.theme
import "Corners.js" as Corners

// Tells Hyprland the screen frame's corner profile, rim and whether a lone window goes flush, so window corners and
// borders follow it (ScreenFrame.set in config/general/frame.lua, which keeps the user's values and restores them on clear or when the frame layer goes).
Scope {
    id: root

    readonly property var profile: Style.screen_frame_profile
    // The whole dispatch, so the debounce restarts on any change; "" with no frame. The radius is the corner as
    // drawn (fitted to its profile's cap), which frame.lua turns into the windows' own rounding.
    readonly property string command: {
        if (!Style.screen_frame_on) return "ScreenFrame.clear()";
        const drawn = Corners.fit(root.profile.corner, root.profile.radius, root.profile.step).radius;
        const args = [JSON.stringify(root.profile.corner), drawn, Style.bar_border_width, JSON.stringify(Corners.hypr_border_color(Style.screen_frame_rim_color(true))), JSON.stringify(Corners.hypr_border_color(Style.screen_frame_rim_color(false))), Style.active.screen_frame_flush !== false];
        return "ScreenFrame.set(" + args.join(", ") + ")";
    }

    function send() {
        Hyprland.dispatch(root.command);
    }

    // The style picker previews frames as it moves, so only the frame it settles on reaches Hyprland.
    onCommandChanged: debounce.restart()

    Timer {
        id: debounce
        interval: 150
        onTriggered: root.send()
    }

    // A Hyprland reload rebuilds the config with the user's values and forgets the saved ones. No teardown on
    // destruction: a Quickshell reload would land it after the new generation's send, and frame.lua's watchdog
    // restores after a quit.
    Component.onCompleted: root.send()

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded") root.send();
        }
    }
}
