import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.core
import qs.theme

// A Hyprland toplevel's live image fitted inside the item, with its app icon until a frame arrives.
Item {
    id: root

    property var toplevel: null
    // Capture runs only while this is set and the item is visible.
    property bool active: true
    property bool live: true
    // Night-vision: shown through a green monochrome pass on AC, plain dimmed on battery.
    property bool tint: false
    readonly property bool tinted: root.tint && root.has_content
    property real icon_size: Math.min(root.width, root.height) * 0.35
    // Shown until a frame arrives; WindowState.icon_for(toplevel) gives the app's.
    property string icon_source: Quickshell.iconPath("application-x-executable", true)
    readonly property bool capturing: root.active && root.visible && !!root.toplevel && !!root.toplevel.wayland
    readonly property bool has_content: !!root.view && root.view.hasContent && root.capturing
    property Item view: null
    // Changes only when the window does: a rebinding that hands over the same window keeps its view and frame.
    property var view_toplevel: null
    onToplevelChanged: if (root.view_toplevel !== root.toplevel) {
        root.view_toplevel = root.toplevel;
        root.retries = 0;
    }
    Component.onCompleted: root.view_toplevel = root.toplevel
    property int retries: 0
    // A thumbnail that spent its retries while shown gets a fresh budget each time it shows again.
    onCapturingChanged: if (root.capturing) root.retries = 0

    // A capture started while another window is closing never delivers a frame (a picker card rebound after `x`),
    // so a view still empty after a moment is replaced by a fresh one, a few times at most.
    Repeater {
        model: root.capturing && root.view_toplevel ? [{ toplevel: root.view_toplevel, attempt: root.retries }] : []

        ScreencopyView {
            id: view
            required property var modelData
            anchors.centerIn: parent
            width: implicitWidth
            height: implicitHeight
            visible: root.has_content
            opacity: root.tinted && !PowerSource.on_ac ? 0.7 : 1
            captureSource: view.modelData.toplevel ? view.modelData.toplevel.wayland : null
            live: root.live
            constraintSize: Qt.size(root.width, root.height)
            Component.onCompleted: root.view = view
            Component.onDestruction: if (root.view === view) root.view = null
        }
    }

    Timer {
        interval: 500
        repeat: true
        running: root.capturing && !root.has_content && root.retries < 4
        onTriggered: root.retries++
    }

    MultiEffect {
        anchors.fill: root.view
        visible: root.tinted && PowerSource.on_ac && !!root.view
        source: root.view
        colorization: 1
        colorizationColor: Style.wk.mid
    }

    IconImage {
        anchors.centerIn: parent
        visible: !root.has_content && root.icon_size > 0
        implicitSize: root.icon_size
        asynchronous: true
        source: root.icon_source
    }
}
