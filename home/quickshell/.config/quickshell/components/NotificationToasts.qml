// home/quickshell/.config/quickshell/components/NotificationToasts.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../theme"
import "../services"

PanelWindow {
    id: root

    readonly property var focused_screen: {
        const mon = Hyprland.focusedMonitor;
        return mon ? Quickshell.screens.find(s => s.name === mon.name) : null;
    }
    screen: root.focused_screen

    readonly property var visible_toasts: NotificationState.toasts.slice(0, NotificationState.max_visible_toasts)
    visible: root.visible_toasts.length > 0

    WlrLayershell.namespace: "quickshell-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    color: "transparent"
    exclusiveZone: 0

    anchors.top: true
    anchors.right: true
    margins.top: 38
    margins.right: 8

    implicitWidth: 400
    implicitHeight: column.implicitHeight

    mask: Region { item: column }

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            model: root.visible_toasts

            NotificationToastCard {
                Layout.fillWidth: true
                required property var modelData
                entry: modelData
            }
        }
    }
}
