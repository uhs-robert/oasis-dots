import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.features.bar
import qs.features.popups
import qs.ui.frames
import "ToastExtent.js" as ToastExtent

PanelWindow {
    id: root

    // The screen focused when the stack last opened; it stays through the show, so a focus change never moves a drawer
    // that is on screen. Same pattern as Osd.
    property string held_screen_name: ""
    screen: Quickshell.screens.find(s => s.name === root.held_screen_name) || null

    readonly property var visible_toasts: NotificationState.visible_toasts
    readonly property bool wanted: root.visible_toasts.length > 0
    visible: root.wanted || root.extent > 0

    function hold_screen() {
        const mon = Hyprland.focusedMonitor;
        root.held_screen_name = mon ? mon.name : "";
    }

    // Only a fully folded window picks up the focused screen; a toast arriving mid-fold stays where it is.
    onWantedChanged: if (root.wanted && root.extent <= 0) root.hold_screen()

    // With the screen frame on, the stack is one drawer at the top right that grows and shrinks with the cards;
    // without one, floating cards each fade and slide in.
    readonly property var screen_frame: root.screen ? ScreenFrames.layout_for(root.screen) : null
    readonly property bool drawer: scaffold.active
    readonly property real screen_width: root.screen ? root.screen.width : 1920
    readonly property real screen_height: root.screen ? root.screen.height : 1080
    readonly property real card_width: 400
    // The window is as deep as a full stack could be, so it never resizes while the shape grows inside it.
    readonly property real window_depth: ToastExtent.window_depth((scaffold.hole ? scaffold.hole.h : root.screen_height) - 2 * (scaffold.cover + scaffold.fillet))

    // How deep the drawer is drawn, easing toward the stack's height (0 when nothing is shown). A Behavior retargets from
    // wherever it is, so a card added or removed, or a toast arriving mid-fold, never restarts or jumps it.
    readonly property real target: root.drawer && root.wanted ? root.stack_height : 0
    property real stack_height: 0
    property real extent: root.target
    property bool snapping: false

    Behavior on extent {
        enabled: !root.snapping
        NumberAnimation {
            id: extent_move
            duration: ToastExtent.opening(root.target, root.extent) ? 190 : 120
            easing.type: ToastExtent.opening(root.target, root.extent) ? Easing.OutCubic : Easing.InCubic
            // A folded window must not hold the keyboard.
            onRunningChanged: if (!extent_move.running && !root.wanted && root.extent <= 0) NotificationState.leave_toast_focus()
        }
    }

    // Cards slide under a still cursor while the drawer moves, so card hover is not acted on until it settles.
    readonly property bool moving: root.drawer && Math.abs(root.extent - root.target) > 0.5

    // A switch of frame or of bar edge while shown restarts from closed instead of sliding across.
    readonly property string bar_edge: root.screen_frame ? root.screen_frame.edge : ""
    onDrawerChanged: root.reset_extent()
    onBar_edgeChanged: root.reset_extent()

    function reset_extent() {
        root.snapping = true;
        root.extent = 0;
        root.snapping = false;
        root.extent = Qt.binding(() => root.target);
    }

    function measure_stack() {
        root.stack_height = ToastExtent.stack_height(column.implicitHeight + ToastExtent.PAD * 2, root.visible_toasts.length, root.stack_height, root.window_depth);
    }
    onVisible_toastsChanged: root.measure_stack()

    WlrLayershell.namespace: "quickshell-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: NotificationState.toast_focus && root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Connections {
        target: NotificationState
        function onToast_focusChanged() {
            if (NotificationState.toast_focus) column.forceActiveFocus();
        }
    }

    Connections {
        target: Popups
        function onOpen_nameChanged() {
            if (Popups.open_name !== "") NotificationState.leave_toast_focus();
        }
    }

    function handle_key(event) {
        const shift = event.modifiers & Qt.ShiftModifier;
        if (event.key === Qt.Key_J) NotificationState.move_toast(1);
        else if (event.key === Qt.Key_K) NotificationState.move_toast(-1);
        else if (event.key === Qt.Key_L) NotificationState.move_toast_action(shift ? 99 : 1);
        else if (event.key === Qt.Key_H) NotificationState.move_toast_action(shift ? -99 : -1);
        else if (event.key === Qt.Key_0) NotificationState.move_toast_action(-99);
        else if (event.text === "$") NotificationState.move_toast_action(99);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) NotificationState.invoke_selected_toast();
        else if (event.key === Qt.Key_D || event.key === Qt.Key_X) NotificationState.dismiss_selected_toast();
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) NotificationState.leave_toast_focus();
        else return;
        event.accepted = true;
    }

    color: "transparent"
    // No explicit exclusiveZone on a drawer: even 0 overrides Ignore, so the frame's zones would push it inward. A
    // floating stack takes the zone 0 default, and a top bar's zone already pushes it below the bar.
    exclusionMode: root.drawer ? ExclusionMode.Ignore : ExclusionMode.Normal

    anchors.top: true
    anchors.right: true
    margins.top: root.drawer ? scaffold.place.margin_top : 8
    margins.right: root.drawer ? scaffold.place.margin_right : 8

    implicitWidth: root.drawer ? scaffold.full.surface.width : root.card_width
    implicitHeight: root.drawer ? scaffold.full.surface.height : column.implicitHeight

    // Live input, unlike the other drawers: clicks and hover reach the cards over the body, and the transparent rest of
    // the window (fillet corners, the unfilled depth) passes them through.
    mask: Region {
        x: root.drawer ? body_clip.x : column.x
        y: root.drawer ? body_clip.y : column.y
        width: root.drawer ? body_clip.width : column.width
        height: root.drawer ? body_clip.height : column.height
    }

    DrawerWindowPublisher {
        screen_name: root.screen ? root.screen.name : ""
        rect: scaffold.window_rect
    }

    TransientDrawer {
        id: scaffold
        screen_frame: root.screen_frame
        screen_name: root.screen ? root.screen.name : ""
        screen_width: root.screen_width
        screen_height: root.screen_height
        side: "right"
        panel_width: root.card_width
        panel_height: root.window_depth
        shown: root.visible
        window_width: root.width
        extent: root.extent
    }

    // The body uncovers the cards as it grows; floating, this is the stack itself and clips nothing.
    Item {
        id: body_clip
        x: root.drawer ? scaffold.body.x : 0
        y: root.drawer ? scaffold.body.y : 0
        width: root.drawer ? scaffold.body.width : root.width
        height: root.drawer ? scaffold.body.height : column.implicitHeight
        clip: root.drawer

        ColumnLayout {
            id: column
            x: root.drawer ? ToastExtent.PAD : 0
            y: root.drawer ? ToastExtent.PAD : 0
            width: parent.width - (root.drawer ? ToastExtent.PAD * 2 : 0)
            spacing: ToastExtent.SPACING
            focus: true

            onImplicitHeightChanged: root.measure_stack()
            Keys.onPressed: event => root.handle_key(event)

            Repeater {
                // Ids, not entries: a model snapshots copies of its objects. ScriptModel keeps the surviving cards alive.
                model: ScriptModel {
                    values: root.visible_toasts.map(e => e.id)
                }

                NotificationToastCard {
                    id: toast_card
                    Layout.fillWidth: true
                    required property var modelData
                    entry: root.visible_toasts.find(e => e.id === toast_card.modelData) || null
                    in_drawer: root.drawer
                    moving: root.moving
                    selected: NotificationState.toast_focus && toast_card.modelData === NotificationState.toast_selected_id
                    focused_action: toast_card.selected ? NotificationState.toast_action : -1
                }
            }
        }
    }
}
