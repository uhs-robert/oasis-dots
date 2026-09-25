// home/quickshell/.config/quickshell/bar/SubmapTab.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components"
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
            // Styles with a clear title show the submap color on the text instead of the fill.
            readonly property bool filled: !Style.show_title || Style.title_bg.a > 0

            y: -height * (1 - root.tab_progress)
            width: label.implicitWidth + 20 + Style.inset_pad * 2
            height: label.implicitHeight + (Style.show_title ? 4 : 2) + Style.inset_pad * 2
            bottomLeftRadius: Style.radius(6)
            bottomRightRadius: Style.radius(6)
            color: tab.filled ? root.shown_color : Style.frame_color
            border.width: Style.show_title ? Style.frame_border_width : 0
            border.color: Style.frame_border_color

            Text {
                id: label
                anchors.centerIn: parent
                text: Style.show_title ? Style.title_prefix + root.shown_name.toUpperCase() + Style.title_suffix : root.shown_name
                color: tab.filled ? Theme.bg_core : root.shown_color
                font.family: Style.font_family
                font.pixelSize: Style.show_title ? Style.font_size - 2 : Style.bar_font_size
                font.bold: true
                font.letterSpacing: Style.show_title ? Style.title_spacing : 0
                style: Style.glow ? Text.Outline : Text.Normal
                styleColor: Qt.alpha(root.shown_color, 0.35)
            }

            // Static scanlines; nothing animates them.
            Repeater {
                model: Style.scanlines ? Math.ceil(tab.height / Style.scanline_period) : 0

                Rectangle {
                    required property int index
                    y: index * Style.scanline_period
                    width: tab.width
                    height: 1
                    color: Qt.alpha(root.shown_color, 0.08)
                }
            }

            FrameInset {
                edge: tab.border.width
                bottom_radius: tab.bottomLeftRadius
            }
        }
    }
}
