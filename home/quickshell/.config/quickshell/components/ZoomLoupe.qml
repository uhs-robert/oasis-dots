// home/quickshell/.config/quickshell/components/ZoomLoupe.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services"
import "picker"

// One per screen: zoom mode's live loupe, shown on the monitor under the pointer.
PanelWindow {
    id: root

    required property var modelData
    readonly property bool mine: Zoom.loupe_shown && Zoom.cursor_screen === root.modelData.name

    readonly property real edge: 24
    readonly property real left_edge: Math.max(0, Math.floor(loupe.x - root.edge))
    readonly property real top_edge: Math.max(0, Math.floor(loupe.y - root.edge))
    readonly property real right_edge: Math.min(root.modelData.width, Math.ceil(loupe.x + loupe.width + root.edge))
    readonly property real bottom_edge: Math.min(root.modelData.height, Math.ceil(loupe.y + loupe.height + root.edge))

    screen: root.modelData
    visible: root.mine
    anchors.top: true
    anchors.left: true
    margins.left: root.left_edge
    margins.top: root.top_edge
    implicitWidth: Math.max(1, root.right_edge - root.left_edge)
    implicitHeight: Math.max(1, root.bottom_edge - root.top_edge)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    WlrLayershell.namespace: "quickshell-zoom"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Binding {
        target: Zoom
        property: "sample_scale"
        value: loupe.sample_scale
        when: root.mine
        restoreMode: Binding.RestoreNone
    }

    // Screen-sized and shifted so the loupe lands on its screen spot inside the small surface.
    Item {
        x: -root.left_edge
        y: -root.top_edge
        width: root.modelData.width
        height: root.modelData.height

        ScreencopyView {
            id: live_view
            anchors.fill: parent
            visible: false
            live: true
            paintCursor: false
            captureSource: root.mine ? root.modelData : null
        }

        Loupe {
            id: loupe
            visible: live_view.hasContent
            at: Zoom.cursor_point
            source: live_view
            sample_scale: live_view.sourceSize.width > 0 ? live_view.sourceSize.width / root.modelData.width : root.modelData.devicePixelRatio
            pixel_mode: false
            screen_name: root.modelData.name
            screen_x: root.modelData.x
            screen_y: root.modelData.y
            area_width: root.modelData.width
            area_height: root.modelData.height
            has_sel: false
            sel: Qt.rect(0, 0, 0, 0)
            pixel_image: ""
            frame_size: Qt.size(0, 0)
            scan_complete: Zoom.scan_complete
            scan_step: Zoom.scan_step
            scan_steps: Zoom.scan_steps
            min_gap: Math.ceil((loupe.half + 1) / loupe.sample_scale) + root.edge + 4
        }
    }
}
