import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.features.bar
import qs.ui.frames
import qs.ui.keys

// The editor's hint bar as a screen-frame drawer, one per screen, for a screen that has the frame: it grows out of the edge
// the bar is not on, like the submap hint bar (features/submap_hints/SubmapHintBar.qml, which this follows). A screen without
// a frame layout keeps HintBox inside BarEditorWindow; the two never show together.
PanelWindow {
    id: root

    required property var modelData
    readonly property bool wanted: BarEditor.keyboard_owner(root.modelData.name) && BarEditor.mode !== "monitor"
    readonly property var bar_item: BarItems.item_of(root.modelData.name, "bar")
    // Same edge rule as BarEditorWindow.hints_on_top.
    readonly property bool on_top: root.bar_item !== null && root.bar_item.position === "bottom"
    readonly property var screen_frame: ScreenFrames.layout_for(root.modelData)
    readonly property bool drawer: scaffold.active

    screen: root.modelData
    // Mapped until the fold ends.
    visible: root.drawer && (root.wanted || scaffold.progress > 0)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors.top: scaffold.place.anchor_top
    anchors.bottom: scaffold.place.anchor_bottom
    anchors.left: scaffold.place.anchor_left
    anchors.right: scaffold.place.anchor_right
    margins.top: scaffold.place.margin_top
    margins.bottom: scaffold.place.margin_bottom
    margins.left: scaffold.place.margin_left
    margins.right: scaffold.place.margin_right
    implicitWidth: scaffold.full.surface.width
    implicitHeight: scaffold.full.surface.height
    WlrLayershell.namespace: "quickshell-bareditor-hints"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    DrawerWindowPublisher {
        screen_name: root.modelData.name
        rect: scaffold.window_rect
    }

    TransientDrawer {
        id: scaffold
        screen_frame: root.screen_frame
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

    // The body uncovers the plate as it grows; the plate rides out with the drawer's far edge.
    Item {
        x: scaffold.body.x
        y: scaffold.body.y
        width: scaffold.body.width
        height: scaffold.body.height
        clip: true

        HintPlate {
            id: plate
            x: (parent.width - plate.width) / 2
            y: scaffold.from_bottom ? 0 : parent.height - plate.height
            plain: true
            width: plate.implicitWidth
            height: plate.implicitHeight
            HintContent {
                anchors.centerIn: parent
                carrying: BarEditor.mode === "hidden" && BarEditor.picked !== ""
                vertical: root.bar_item !== null && root.bar_item.vertical
            }
        }
    }
}
