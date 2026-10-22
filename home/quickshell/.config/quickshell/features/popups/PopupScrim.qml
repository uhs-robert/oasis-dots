import QtQuick
import Quickshell
import Quickshell.Wayland

// Below the bar's reserved zone, so bar clicks still switch popups. With a screen frame the bar reserves nothing, so
// the scrim spans the screen, bands included, with the bar's rect cut out of its input instead.
PanelWindow {
    id: root

    // The screen frame's layout (FrameGeometry.frame_layout), or null.
    property var frame: null
    readonly property real bar_depth: root.frame && root.frame.has_bar ? root.frame.near : 0

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    // -1 ignores the frame's zones, as the frame and bar windows do.
    exclusiveZone: root.frame ? -1 : 0
    color: "transparent"
    visible: Popups.open_name !== ""
    WlrLayershell.namespace: "quickshell-scrim"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Popups.hands_off ? no_input : root.frame ? outside_bar : null

    Region {
        id: no_input
    }

    Region {
        id: outside_bar
        item: catcher

        Region {
            x: 0
            y: root.frame && root.frame.edge === "bottom" ? root.height - root.bar_depth : 0
            width: root.width
            height: root.bar_depth
            intersection: Intersection.Subtract
        }
    }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: Popups.close()
    }
}
