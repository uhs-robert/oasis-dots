// home/quickshell/.config/quickshell/components/WindowThumbnail.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../services"

// A Hyprland toplevel's live image fitted inside the item, with its app icon until a frame arrives.
Item {
    id: root

    property var toplevel: null
    // Capture runs only while this is set and the item is visible.
    property bool active: true
    property bool live: true
    property real icon_size: Math.min(root.width, root.height) * 0.35
    readonly property bool capturing: root.active && root.visible && !!root.toplevel && !!root.toplevel.wayland
    readonly property bool has_content: view.hasContent && root.capturing

    ScreencopyView {
        id: view
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        visible: root.has_content
        captureSource: root.capturing ? root.toplevel.wayland : null
        live: root.live && root.capturing
        constraintSize: Qt.size(root.width, root.height)
    }

    IconImage {
        anchors.centerIn: parent
        visible: !root.has_content && root.icon_size > 0
        implicitSize: root.icon_size
        asynchronous: true
        source: root.toplevel ? WindowState.icon_for(root.toplevel) : Quickshell.iconPath("application-x-executable", true)
    }
}
