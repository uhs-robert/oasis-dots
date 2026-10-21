import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.features.lock
import qs.features.settings

// A tiny overlay square in the bar's start corner (top-left, or bottom-left under a bottom bar): resting the pointer there opens the overview.
PanelWindow {
    id: root

    property var overview: null
    property bool bottom: false

    readonly property int dwell_ms: 250
    readonly property var monitor: Hyprland.monitorFor(root.screen)
    property bool fired: false

    // A corner shared with a neighbouring monitor is no wall for the pointer, so only outer corners act.
    readonly property bool reachable: {
        const sc = root.screen;
        if (!sc) return false;
        const covers = (s, x, y) => s !== sc && x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height;
        const corner_y = root.bottom ? sc.y + sc.height - 1 : sc.y;
        return !Quickshell.screens.some(s => covers(s, sc.x - 1, corner_y) || covers(s, sc.x, root.bottom ? corner_y + 1 : corner_y - 1));
    }

    function fullscreen_here() {
        const ws = root.monitor ? root.monitor.activeWorkspace : null;
        return !!ws && !!ws.lastIpcObject && !!ws.lastIpcObject.hasfullscreen;
    }

    function fire() {
        if (!root.fullscreen_here() && root.overview) root.overview.show_overview();
    }

    visible: root.reachable && HotCornersSettings.enabled && !Lock.locked
    color: "transparent"
    implicitWidth: 3
    implicitHeight: 3
    exclusionMode: ExclusionMode.Ignore
    anchors.top: !root.bottom
    anchors.bottom: root.bottom
    anchors.left: true
    WlrLayershell.namespace: "quickshell-hotcorner"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hover.hovered) {
                Hyprland.refreshWorkspaces();
                dwell.restart();
            } else {
                dwell.stop();
                // The overview covering the corner is not a real leave; closing it must not refire.
                if (!root.overview || !root.overview.wanted) root.fired = false;
            }
        }
    }

    Timer {
        id: dwell
        interval: root.dwell_ms
        onTriggered: {
            if (root.fired || !hover.hovered) return;
            root.fired = true;
            root.fire();
        }
    }
}
