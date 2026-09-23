// home/quickshell/.config/quickshell/components/Popup.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

PanelWindow {
    id: root

    property string popup_name: ""
    property real preferred_width: 260
    // Set while a native menu from this popup is open; focus returns to the popup when it closes.
    property bool suspend_grab: false

    property var tabs: []
    property int current_tab: 0
    // The current tab's sub-view names; each tab keeps its own current_sub across tab switches.
    property var sub_views: []
    property int current_sub: 0
    // gg/G emit jump_first/jump_last only while set; the popup owns what first and last mean.
    property bool jumps_enabled: false
    signal jump_first()
    signal jump_last()

    property var sub_memory: ({})
    property double last_g_ms: 0

    onTabsChanged: if (current_tab >= tabs.length) current_tab = 0
    onCurrent_tabChanged: current_sub = sub_memory[current_tab] || 0
    onCurrent_subChanged: sub_memory[current_tab] = current_sub

    function set_tab(i) {
        if (tabs.length > 0) current_tab = Math.max(0, Math.min(tabs.length - 1, i));
    }

    function step_tab(delta) {
        if (tabs.length > 0) current_tab = (current_tab + delta + tabs.length) % tabs.length;
    }

    function step_sub(delta) {
        if (sub_views.length > 0) current_sub = (current_sub + delta + sub_views.length) % sub_views.length;
    }

    // Runs after the popup's own handlers: keys reach it only when nothing deeper accepted them.
    function handle_shared_key(event) {
        const focus_item = content_scope.Window.activeFocusItem;
        if (focus_item && "cursorPosition" in focus_item) return;
        const back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
        if (event.key === Qt.Key_Q) {
            Popups.close();
        } else if (tabs.length > 0 && event.key === Qt.Key_BracketLeft) {
            step_tab(-1);
        } else if (tabs.length > 0 && event.key === Qt.Key_BracketRight) {
            step_tab(1);
        } else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + Math.min(9, tabs.length)) {
            set_tab(event.key - Qt.Key_1);
        } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (tabs.length > 0 || sub_views.length > 0)) {
            step_sub(back ? -1 : 1);
        } else if (jumps_enabled && event.key === Qt.Key_G) {
            if (event.modifiers & Qt.ShiftModifier) {
                jump_last();
            } else {
                const now_ms = Date.now();
                if (now_ms - last_g_ms < 500) {
                    last_g_ms = 0;
                    jump_first();
                } else {
                    last_g_ms = now_ms;
                }
            }
        } else {
            return;
        }
        event.accepted = true;
    }

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
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

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
        } else if (visible) {
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
                Keys.onPressed: event => root.handle_shared_key(event)
            }
        }
    }

    onSuspend_grabChanged: if (!root.suspend_grab && root.visible) content_scope.forceActiveFocus()
}
