import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.ui.frames
import qs.ui.keys

// The window both hint bars share (features/submap_hints/SubmapHintBar.qml, features/bar_editor/HintDrawerWindow.qml), one
// per screen, shown while `wanted`. With the screen frame on it is a plain-centre TransientDrawer on the edge the bar is not
// on, grown out of the frame and folded back, like the OSD; with `floating_fallback` a screen without the frame keeps a
// floating plate instead, otherwise the window stays hidden there. Display only: the caller's content is the plate's one child,
// and the plate takes its size. The caller holds any content that must outlive `wanted` through the fold.
PanelWindow {
    id: root

    required property var modelData
    property string namespace: ""
    // The caller's gate; a change mid-way reverses the animation from where it is.
    property bool wanted: false
    property bool floating_fallback: false
    default property alias content: plate.contents

    readonly property var bar_item: BarItems.item_of(root.modelData.name, "bar")
    readonly property bool on_top: root.bar_item !== null && root.bar_item.position === "bottom"
    readonly property bool drawer: scaffold.active
    // How far the drawer has grown, 0 to 1; a caller that swaps content waits for 0.
    readonly property real progress: scaffold.progress
    readonly property int edge_gap: 24

    screen: root.modelData
    // A drawer stays mapped until its fold ends.
    visible: (root.wanted && (root.drawer || root.floating_fallback)) || (root.drawer && scaffold.progress > 0)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors.top: root.drawer ? scaffold.place.anchor_top : root.on_top
    anchors.bottom: root.drawer ? scaffold.place.anchor_bottom : !root.on_top
    anchors.left: root.drawer ? scaffold.place.anchor_left : false
    anchors.right: root.drawer ? scaffold.place.anchor_right : false
    margins.top: root.drawer ? scaffold.place.margin_top : root.edge_gap
    margins.bottom: root.drawer ? scaffold.place.margin_bottom : root.edge_gap
    margins.left: root.drawer ? scaffold.place.margin_left : 0
    margins.right: root.drawer ? scaffold.place.margin_right : 0
    implicitWidth: root.drawer ? scaffold.full.surface.width : plate.width
    implicitHeight: root.drawer ? scaffold.full.surface.height : plate.height
    WlrLayershell.namespace: root.namespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    // Lets the frame and the strip leave their lines out under the window, while it is mapped.
    DrawerWindowPublisher {
        screen_name: root.modelData.name
        rect: scaffold.window_rect
    }

    TransientDrawer {
        id: scaffold
        screen_frame: ScreenFrames.layout_for(root.modelData)
        screen_name: root.modelData.name
        screen_width: root.modelData.width
        screen_height: root.modelData.height
        side: "center"
        from_bottom: !root.on_top
        panel_width: plate.implicitWidth
        panel_height: plate.implicitHeight
        shown: root.visible
        window_width: root.width
        window_height: root.height
    }

    function refresh() {
        if (!root.drawer) return;
        if (root.wanted) {
            scaffold.close_anim.stop();
            if (scaffold.progress < 1 && !scaffold.open_anim.running) scaffold.open_anim.start();
        } else {
            scaffold.open_anim.stop();
            if (scaffold.progress > 0 && !scaffold.close_anim.running) scaffold.close_anim.start();
        }
    }

    // A change of edge or of frame restarts from closed instead of sliding across.
    function restart() {
        scaffold.open_anim.stop();
        scaffold.close_anim.stop();
        scaffold.progress = 0;
        root.refresh();
    }

    onWantedChanged: root.refresh()
    onDrawerChanged: root.restart()
    onOn_topChanged: root.restart()
    Component.onCompleted: root.refresh()

    // The drawer's body uncovers the plate as it grows; floating, this is the whole window and clips nothing.
    Item {
        id: clip_box
        x: root.drawer ? scaffold.body.x : 0
        y: root.drawer ? scaffold.body.y : 0
        width: root.drawer ? scaffold.body.width : root.width
        height: root.drawer ? scaffold.body.height : root.height
        clip: root.drawer

        HintPlate {
            id: plate
            // The plate rides out with the drawer's far edge instead of staying put while the body uncovers it.
            x: root.drawer ? (clip_box.width - plate.width) / 2 : 0
            y: root.drawer && !scaffold.from_bottom ? clip_box.height - plate.height : 0
            plain: root.drawer
            width: plate.implicitWidth
            height: plate.implicitHeight
        }
    }
}
