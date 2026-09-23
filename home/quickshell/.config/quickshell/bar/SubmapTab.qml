// home/quickshell/.config/quickshell/bar/SubmapTab.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

PanelWindow {
    id: root

    property real line_width: 260
    property bool bar_present: true
    property string shown_name: ""
    property color shown_color: Theme.theme_secondary
    property real line_progress: 0
    property real tab_progress: 0

    visible: false
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-submap"
    anchors.top: true
    implicitWidth: Math.max(line_width, tab.width)
    implicitHeight: line.height + tab.height
    mask: Region {}

    // Keeps the last name and color on screen while the hide animation plays.
    Connections {
        target: SubmapState

        function onSubmap_nameChanged() {
            if (!root.bar_present) return;
            if (SubmapState.active) {
                root.shown_name = SubmapState.submap_name;
                root.shown_color = SubmapState.submap_color;
                hide_anim.stop();
                if (!root.visible || root.line_progress < 1) {
                    root.visible = true;
                    show_anim.restart();
                }
            } else {
                show_anim.stop();
                hide_anim.restart();
            }
        }
    }

    SequentialAnimation {
        id: show_anim
        NumberAnimation { target: root; property: "line_progress"; to: 1; duration: 140; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "tab_progress"; to: 1; duration: 140; easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: hide_anim
        NumberAnimation { target: root; property: "tab_progress"; to: 0; duration: 90; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "line_progress"; to: 0; duration: 90; easing.type: Easing.InCubic }
        ScriptAction { script: root.visible = false }
    }

    Rectangle {
        id: line
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.line_width * root.line_progress
        height: 3
        color: root.shown_color
    }

    Item {
        anchors.top: line.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: tab.width
        height: tab.height
        clip: true

        Rectangle {
            id: tab
            y: -height * (1 - root.tab_progress)
            width: label.implicitWidth + 20
            height: label.implicitHeight + 2
            bottomLeftRadius: 6
            bottomRightRadius: 6
            color: root.shown_color

            Text {
                id: label
                anchors.centerIn: parent
                text: root.shown_name
                color: Theme.bg_core
                font.family: Theme.font_family
                font.pixelSize: Theme.font_size
                font.bold: true
            }
        }
    }
}
