import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.theme
import qs.features.voice

PanelWindow {
    id: root

    // How long the line is: the center island's extent along the bar.
    property real line_width: 260
    property bool bar_present: true
    // The bar sits on the bottom edge: the line and tabs rise above it instead of hanging below.
    property bool bottom: false
    // "left" or "right" when the bar is a column: the line runs down the bar's open edge (the layer sits beside the bar,
    // as a top bar's sits below it) and the tabs, turned a quarter, hang from it. Empty on a top or bottom bar.
    property string side: ""
    readonly property bool vertical: root.side !== ""
    readonly property real line_thickness: 3
    // The bar on this screen shows the submap in a lualine mode chip instead.
    property bool chip_shown: false
    property string submap_name: ""
    property color submap_color: Theme.theme_secondary
    // Only the focused monitor shows the tab, so a submap opens one window instead of one per bar.
    property string screen_name: ""
    readonly property bool focused: !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === root.screen_name
    property string voice_name: ""
    property color voice_color: Theme.theme_secondary
    readonly property bool want_submap: SubmapState.indicator_shown && !root.chip_shown && root.focused
    readonly property bool want_voice: VoxSessionState.active && root.focused
    property real line_progress: 0
    // Tabs drop once the line has drawn and lift before it retracts.
    property real submap_progress: root.want_submap && root.line_progress >= 1 ? 1 : 0
    property real voice_progress: root.want_voice && root.line_progress >= 1 ? 1 : 0

    visible: false
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-submap"
    anchors.top: !root.vertical && !root.bottom
    anchors.bottom: !root.vertical && root.bottom
    anchors.left: root.side === "left"
    anchors.right: root.side === "right"
    implicitWidth: root.vertical ? root.line_thickness + tabs.height : Math.max(line_width, tabs.width)
    implicitHeight: root.vertical ? Math.max(line_width, tabs.width) : root.line_thickness + tabs.height
    mask: Region {}

    onWant_submapChanged: root.sync()
    onWant_voiceChanged: root.sync()

    Behavior on submap_progress {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    Behavior on voice_progress {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    // Keeps the last names and colors on screen while the hide animation plays.
    function sync() {
        if (!root.bar_present) return;
        if (root.want_submap) {
            root.submap_name = SubmapState.submap_name;
            root.submap_color = SubmapState.bar_color;
        }
        if (root.want_voice) {
            root.voice_name = VoxSessionState.label;
            root.voice_color = VoxSessionState.mode_color;
        }
        if (root.want_submap || root.want_voice) {
            hide_anim.stop();
            if (!root.visible || root.line_progress < 1) {
                root.visible = true;
                show_anim.restart();
            }
        } else if (root.visible) {
            show_anim.stop();
            hide_anim.restart();
        }
    }

    Connections {
        target: SubmapState

        function onSubmap_nameChanged() {
            root.sync();
        }
    }

    Connections {
        target: VoxSessionState

        function onLabelChanged() {
            root.sync();
        }

        function onKindChanged() {
            root.sync();
        }
    }

    NumberAnimation { id: show_anim; target: root; property: "line_progress"; to: 1; duration: 140; easing.type: Easing.OutCubic }

    // The pause lets the tabs lift first.
    SequentialAnimation {
        id: hide_anim
        PauseAnimation { duration: 90 }
        NumberAnimation { target: root; property: "line_progress"; to: 0; duration: 90; easing.type: Easing.InCubic }
        ScriptAction { script: root.visible = false }
    }

    Rectangle {
        id: line
        // Placed by x and y, not anchors: an anchor switched off leaves its last x or y behind.
        x: root.vertical ? (root.side === "right" ? tabs.height : 0) : (root.width - line.width) / 2
        y: root.vertical ? (root.height - line.height) / 2 : root.bottom ? tabs.height : 0
        width: root.vertical ? root.line_thickness : root.line_width * root.line_progress
        height: root.vertical ? root.line_width * root.line_progress : root.line_thickness
        // The submap owns the line while both tabs show.
        color: root.submap_progress > 0 || root.want_submap ? root.submap_color : root.voice_color
    }

    // The voice mode sits beside the submap tab, so both stay readable when a submap is open during a session.
    Row {
        id: tabs
        // Turned about its top-left corner, so x and y name the corner the turned row grows from: its top edge (where
        // it hangs from the line) faces the bar, so the text reads upward on a left bar and downward on a right one.
        transformOrigin: Item.TopLeft
        rotation: root.side === "left" ? -90 : root.side === "right" ? 90 : 0
        x: root.side === "left" ? root.line_thickness : root.side === "right" ? tabs.height : (root.width - tabs.width) / 2
        y: root.vertical ? (root.side === "left" ? (root.height + tabs.width) / 2 : (root.height - tabs.width) / 2) : root.bottom ? 0 : root.line_thickness
        // A Row counts only visible children, so without this its height (and the window's) jumps when a tab first shows.
        height: Math.max(submap_tab.height, voice_tab.height)
        spacing: 6

        ModeTab {
            id: submap_tab
            name: root.submap_name
            tint: root.submap_color
            progress: root.submap_progress
            rises: root.bottom
        }

        ModeTab {
            id: voice_tab
            name: root.voice_name
            tint: root.voice_color
            progress: root.voice_progress
            rises: root.bottom
        }
    }
}
