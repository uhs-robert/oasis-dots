import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.theme
import "../../ui/frames/Corners.js" as Corners
import "../../theme/FrameTokens.js" as FrameTokens
import "BarLayout.js" as BarLayout

// Tells Hyprland the Corner style, and with the frame on its rim and whether a lone window goes flush, so window
// corners (and with the frame, borders) follow it (ScreenFrame.set in config/general/frame.lua, which keeps the user's
// values and restores them on clear or when Quickshell goes).
Scope {
    id: root

    readonly property var profile: Style.corner_profile
    // The whole dispatch, so the debounce restarts on any change. A frame on but drawn on no screen (only side bars)
    // goes as a frame-off corner, like FrameExport's, and a clear leaves the owner's values. The radius is the corner
    // as drawn (fitted to its profile's cap), which frame.lua turns into the windows' own rounding; Flush is the
    // Style page's setting. The framed monitor list goes last, so an older frame.lua ignores it and frames every monitor.
    readonly property string command: {
        const mode = Style.sync_mode(ScreenFrames.any_frame);
        if (mode === "clear") return "ScreenFrame.clear()";
        const frame = mode === "frame";
        const drawn = Corners.fit(root.profile.corner, root.profile.radius, root.profile.step).radius;
        const args = [JSON.stringify(root.profile.corner), drawn, Style.screen_frame_rim_width, JSON.stringify(Corners.hypr_border_color(Style.screen_frame_rim_color(true))), JSON.stringify(Corners.hypr_border_color(Style.screen_frame_rim_color(false))), Style.flush_single, frame, Quickshell.processId, FrameTokens.lua_string_list(root.framed_monitors)];
        return "ScreenFrame.set(" + args.join(", ") + ")";
    }

    // A side bar's screen draws no frame, so its windows keep the owner's look. Hyprland's description, not Qt's model,
    // since frame.lua matches it against Hyprland's monitors.
    readonly property var framed_monitors: FrameTokens.framed_monitors(Quickshell.screens.map(s => {
        const monitor = Hyprland.monitorFor(s);
        return {
            name: s.name,
            description: monitor ? monitor.description : "",
            framed: BarLayout.draws_frame(Style.screen_frame_on, ScreenFrames.position_for_screen(s))
        };
    }))

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
