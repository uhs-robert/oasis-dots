// home/quickshell/.config/quickshell/components/picker/cursors/Tmux.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"

// tmux copy-mode cursor for the Terminal picker skin: a blinking 9x17 block
// over the point, and a top-right position/size tag in the status bar colors.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property bool target_mode

    property point at: Screenshot.cursor_point
    property bool shown: Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name
    readonly property int cx: Math.round(root.at.x)
    readonly property int cy: Math.round(root.at.y)
    readonly property bool dragging: Screenshot.sel_screen === root.screen_name && Screenshot.has_selection && Screenshot.phase === "select"
    readonly property string tag_text: root.dragging ? "[" + Math.round(Screenshot.sel_rect.width) + "x" + Math.round(Screenshot.sel_rect.height) + "]" : "[" + root.cy + "/" + root.cx + "]"

    visible: Style.picker_skin === "tmux" && root.shown && !root.target_mode

    onAtChanged: block_blink.show()

    Timer {
        id: block_blink
        interval: 1000
        repeat: true
        running: root.visible
        onTriggered: block.opacity = block.opacity > 0 ? 0 : 1

        function show() {
            block.opacity = 1;
            block_blink.restart();
        }
    }

    Rectangle {
        id: block
        x: root.cx - width / 2
        y: root.cy - height / 2
        width: 9
        height: 17
        color: Theme.fg_core
    }

    Rectangle {
        id: pos_tag
        anchors.top: parent.top
        anchors.topMargin: 30
        anchors.right: parent.right
        anchors.rightMargin: 10
        width: pos_text.implicitWidth + 12
        height: pos_text.implicitHeight + 4
        color: Theme.ui_match_bg

        Text {
            id: pos_text
            anchors.centerIn: parent
            text: root.tag_text
            color: Theme.bg_core
            font.family: Style.mono_font
            font.pixelSize: 13
        }
    }
}
