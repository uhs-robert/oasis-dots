// home/quickshell/.config/quickshell/components/picker/cursors/Nvimfloat.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"

// Neovim picker skin: a cursorline/cursorcolumn band pair through the point and a
// reverse-video block cursor, like moving the cursor in a Neovim buffer.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property bool target_mode

    property point at: Screenshot.cursor_point
    property bool shown: Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name
    readonly property int cx: Math.round(root.at.x)
    readonly property int cy: Math.round(root.at.y)

    visible: Style.picker_skin === "nvimfloat" && root.shown && !root.target_mode

    Rectangle {
        x: 0
        y: root.cy - 8
        width: root.width
        height: 16
        color: Qt.alpha(Theme.ui_cursor_line, 0.55)
    }

    Rectangle {
        x: root.cx - 4
        y: 0
        width: 8
        height: root.height
        color: Qt.alpha(Theme.ui_cursor_line, 0.55)
    }

    Rectangle {
        x: root.cx - 4
        y: root.cy - 8
        width: 8
        height: 16
        color: Qt.alpha(Theme.fg_core, 0.85)
    }
}
