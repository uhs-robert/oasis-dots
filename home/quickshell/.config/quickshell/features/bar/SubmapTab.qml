import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.theme
import qs.features.voice

PanelWindow {
    id: root

    property real line_width: 260
    property bool bar_present: true
    // The bar sits on the bottom edge: the line and tabs rise above it instead of hanging below.
    property bool bottom: false
    // The bar on this screen shows the submap in a lualine mode chip instead.
    property bool chip_shown: false
    property string submap_name: ""
    property color submap_color: Theme.theme_secondary
    // Only the focused monitor shows the tab, so a submap opens one window instead of one per bar.
    property string screen_name: ""
    readonly property bool focused: !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === root.screen_name
    property string voice_name: ""
    property color voice_color: Theme.theme_secondary
    readonly property bool want_submap: SubmapState.active && !root.chip_shown && root.focused
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
    anchors.top: !root.bottom
    anchors.bottom: root.bottom
    implicitWidth: Math.max(line_width, tabs.width)
    implicitHeight: line.height + tabs.height
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
        y: root.bottom ? tabs.height : 0
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.line_width * root.line_progress
        height: 3
        // The submap owns the line while both tabs show.
        color: root.submap_progress > 0 || root.want_submap ? root.submap_color : root.voice_color
    }

    // The voice mode sits beside the submap tab, so both stay readable when a submap is open during a session.
    Row {
        id: tabs
        y: root.bottom ? 0 : line.height
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6

        ModeTab {
            name: root.submap_name
            tint: root.submap_color
            progress: root.submap_progress
            rises: root.bottom
        }

        ModeTab {
            name: root.voice_name
            tint: root.voice_color
            progress: root.voice_progress
            rises: root.bottom
        }
    }
}
