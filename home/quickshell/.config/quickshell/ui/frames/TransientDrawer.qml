import QtQuick
import qs.theme
import "DrawerGeometry.js" as Drawer
import "FrameGeometry.js" as FrameGeometry

// The scaffolding a transient surface (OSD, which-key HUD, toasts) shares to be a screen-frame drawer: the geometry from its
// panel size, the placement for its window, the shape drawn under its content and the open and close animations. The
// host window keeps its own anchors, lifecycle and content, and publishes `window_rect` itself
// (features/bar/DrawerWindowPublisher.qml needs ScreenFrames, which a ui/ file may not import).
Item {
    id: root

    // The screen's frame layout (ScreenFrames.layout_for), or null for a floating surface.
    property var screen_frame: null
    property string screen_name: ""
    property real screen_width: 1920
    property real screen_height: 1080
    // The end of the attached edge that is a pocket ("left", "right"), or "center" for a fillet at both.
    property string side: "center"
    property bool from_bottom: false
    // The panel's natural size; the drawer's body is this wide and its depth grows to this tall.
    property real panel_width: 0
    property real panel_height: 0
    // The window's mapped state and width, for `window_rect`.
    property bool shown: false
    property real window_width: 0

    // How far the drawer has grown, 0 to 1. The default `extent` follows it; a host that sizes the drawer in pixels
    // sets `extent` and leaves it alone.
    property real progress: 0
    property real extent: root.active ? root.panel_height * root.progress : 0

    // Plays after close_anim completes, not when it is stopped.
    signal closed

    readonly property bool active: root.screen_frame !== null
    readonly property var profile: root.active ? Style.screen_frame_profile : null
    readonly property real fillet: root.profile ? Drawer.fillet_of(root.profile) : 0
    readonly property real cover: Drawer.cover_depth(Style.bar_border_width, Style.bar_inset_gap, Style.bar_inset_width)
    readonly property var hole: root.screen_frame ? FrameGeometry.hole_rect(root.screen_frame) : null
    readonly property var kinds: Drawer.end_kinds(root.side, false)

    function spec(extent) {
        return Object.assign({
            edge: root.from_bottom ? "bottom" : "top",
            body_length: root.hole ? Drawer.body_length(root.side, root.panel_width, root.hole.w, root.fillet) : root.panel_width,
            body_depth: root.panel_height,
            extent: extent,
            start_kind: root.kinds.start,
            end_kind: root.kinds.end,
            cover: root.cover
        }, Drawer.profile_fields(root.profile));
    }

    // The window follows the full drawer, so it never resizes while the shape grows inside it. Never null, so a frame
    // switched off under an open window cannot leave DrawerShape without a layout.
    readonly property var full: Drawer.drawer_layout(root.spec(root.panel_height))
    readonly property var layout: Drawer.drawer_layout(root.spec(root.extent))
    readonly property var body: Drawer.body_rect(root.layout)
    readonly property var place: Drawer.place(root.side, root.from_bottom, root.hole, root.screen_frame ? FrameGeometry.seam_of(root.screen_frame, root.from_bottom ? "bottom" : "top") : 0, root.screen_width, root.screen_height, root.cover, root.full.length)
    // Where the drawer's texture tiles from, so it runs on from the frame's (DrawerShape).
    readonly property var texture_origin: Drawer.texture_origin(root.side, root.from_bottom, !!root.screen_frame && root.screen_frame.edge === "bottom", root.place, root.screen_width, root.screen_height, root.full.length)
    readonly property bool translucent: root.active && Style.islands_translucent
    // For the host's DrawerWindowPublisher; null while the frame and the strip need not leave their lines out.
    readonly property var window_rect: root.translucent && root.shown ? Drawer.window_rect(root.side, root.from_bottom, root.place, root.screen_width, root.screen_height, root.window_width, root.layout.drawn_depth) : null

    property alias open_anim: opening
    property alias close_anim: closing

    NumberAnimation {
        id: opening
        target: root
        property: "progress"
        to: 1
        duration: 190
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: closing
        NumberAnimation { target: root; property: "progress"; to: 0; duration: 120; easing.type: Easing.InCubic }
        ScriptAction { script: root.closed() }
    }

    Loader {
        active: root.active
        sourceComponent: DrawerShape {
            layout: root.layout
            screen_name: root.screen_name
            translucent: root.translucent
            texture_origin: root.texture_origin
            frame: root.screen_frame
        }
    }
}
