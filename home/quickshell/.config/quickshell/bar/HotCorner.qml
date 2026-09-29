// home/quickshell/.config/quickshell/bar/HotCorner.qml
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../lock"
import "../services"

// A tiny overlay square in the top-left corner: resting the pointer there opens the overview.
PanelWindow {
    id: root

    property var overview: null

    readonly property int dwell_ms: 250
    readonly property var monitor: Hyprland.monitorFor(root.screen)
    property bool fired: false

    // A corner shared with a neighbouring monitor is no wall for the pointer, so only outer corners act.
    readonly property bool reachable: {
        const sc = root.screen;
        if (!sc) return false;
        const covers = (s, x, y) => s !== sc && x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height;
        return !Quickshell.screens.some(s => covers(s, sc.x - 1, sc.y) || covers(s, sc.x, sc.y - 1));
    }

    function fullscreen_here() {
        const ws = root.monitor ? root.monitor.activeWorkspace : null;
        return !!ws && !!ws.lastIpcObject && !!ws.lastIpcObject.hasfullscreen;
    }

    function fire() {
        if (!root.fullscreen_here() && root.overview) root.overview.show_overview();
    }

    visible: root.reachable && HotCorners.enabled && !Lock.locked
    color: "transparent"
    implicitWidth: 3
    implicitHeight: 3
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
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
