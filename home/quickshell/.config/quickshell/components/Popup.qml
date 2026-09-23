// home/quickshell/.config/quickshell/components/Popup.qml
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../theme"
import "../services"

PanelWindow {
    id: root

    property string popup_name: ""
    property real preferred_width: 260
    // Set while a native menu from this popup is open, so the focus grab doesn't close us.
    property bool suspend_grab: false

    // Never narrower than the island's bottom edge (its body, between the slants).
    implicitWidth: Math.max(preferred_width, island_width)
    default property alias content: content_scope.data

    readonly property bool wanted: Popups.open_name === root.popup_name && Popups.open_screen_name !== ""

    // Latched on open so the popup keeps its place and color while the close animation plays.
    property var held_anchor: null
    property string held_screen_name: ""
    property color held_color: Theme.bg_mantle

    // The anchor is the island's body; its parent is the Island, which knows which end caps it has.
    readonly property var island: held_anchor ? held_anchor.parent : null
    readonly property real island_width: held_anchor ? held_anchor.width : 0
    readonly property bool island_cap_left: !!island && island.cap_left === true
    readonly property bool island_cap_right: !!island && island.cap_right === true
    // cap_right-only = a left island, flush with the screen's left edge; cap_left-only = a right island.
    readonly property string side: (island_cap_left && island_cap_right) ? "center" : island_cap_right ? "left" : island_cap_left ? "right" : "center"

    // A layer surface pinned to the screen edge: xdg popups landed a few px short of it.
    screen: Quickshell.screens.find(s => s.name === root.held_screen_name) || null
    anchors.top: true
    anchors.left: side === "left"
    anchors.right: side === "right"
    exclusiveZone: 0
    color: "transparent"
    visible: false
    WlrLayershell.namespace: "quickshell-popup"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.wanted && !root.suspend_grab ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

    readonly property int line_height: 3
    property real line_progress: 0
    property real drop_progress: 0

    onWantedChanged: {
        if (wanted) {
            close_anim.stop();
            held_anchor = Popups.open_anchor;
            held_screen_name = Popups.open_screen_name;
            held_color = Popups.open_color;
            visible = true;
            open_anim.restart();
            content_scope.forceActiveFocus();
            Qt.callLater(() => focus_grab.active = root.visible && root.wanted && !root.suspend_grab);
        } else if (visible) {
            focus_grab.active = false;
            open_anim.stop();
            close_anim.restart();
        }
    }

    // Plays once per open or close: the accent line draws out to the island's width from the screen edge (center: the middle),
    // then the body drops from it; closing folds back the same way.
    SequentialAnimation {
        id: open_anim
        NumberAnimation { target: root; property: "line_progress"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "drop_progress"; to: 1; duration: 190; easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: close_anim
        NumberAnimation { target: root; property: "drop_progress"; to: 0; duration: 120; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "line_progress"; to: 0; duration: 90; easing.type: Easing.InCubic }
        ScriptAction {
            script: {
                root.visible = false;
                root.held_anchor = null;
            }
        }
    }

    function edge_x(w) {
        return side === "right" ? width - w : side === "left" ? 0 : (width - w) / 2;
    }

    Rectangle {
        id: accent_line
        readonly property real w: root.island_width * root.line_progress
        x: root.edge_x(w)
        width: w
        height: root.line_height
        color: Theme.theme_primary
        opacity: root.line_progress > 0 ? 1 : 0
        z: 1
    }

    Item {
        id: reveal
        y: root.line_height
        width: root.width
        height: (root.height - root.line_height) * root.drop_progress
        clip: true

        Item {
            width: root.width
            height: root.height - root.line_height

            // Reads as the island unfolding downward: its color, joined flush under the accent line.
            Rectangle {
                anchors.fill: parent
                color: root.held_color
                bottomLeftRadius: 10
                bottomRightRadius: 10
            }

            FocusScope {
                id: content_scope
                anchors.fill: parent
                focus: true

                Keys.onEscapePressed: Popups.close()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Q) {
                        Popups.close();
                        event.accepted = true;
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        id: focus_grab
        windows: [root]
        onCleared: Popups.close()
    }

    onSuspend_grabChanged: {
        focus_grab.active = root.visible && root.wanted && !root.suspend_grab;
        if (!root.suspend_grab && root.visible) content_scope.forceActiveFocus();
    }
}
