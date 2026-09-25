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

    readonly property var visible_toasts: NotificationState.visible_toasts
    visible: root.visible_toasts.length > 0

    WlrLayershell.namespace: "quickshell-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: NotificationState.toast_focus ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Connections {
        target: NotificationState
        function onToast_focusChanged() {
            if (NotificationState.toast_focus) column.forceActiveFocus();
        }
    }

    Connections {
        target: Popups
        function onOpen_nameChanged() {
            if (Popups.open_name !== "") NotificationState.leave_toast_focus();
        }
    }

    function handle_key(event) {
        const shift = event.modifiers & Qt.ShiftModifier;
        if (event.key === Qt.Key_J) NotificationState.move_toast(1);
        else if (event.key === Qt.Key_K) NotificationState.move_toast(-1);
        else if (event.key === Qt.Key_L) NotificationState.move_toast_action(shift ? 99 : 1);
        else if (event.key === Qt.Key_H) NotificationState.move_toast_action(shift ? -99 : -1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) NotificationState.invoke_selected_toast();
        else if (event.key === Qt.Key_D || event.key === Qt.Key_X) NotificationState.dismiss_selected_toast();
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) NotificationState.leave_toast_focus();
        else return;
        event.accepted = true;
    }

    color: "transparent"
    exclusiveZone: 0

    anchors.top: true
    anchors.right: true
    margins.top: BarConfig.height_for(BarConfig.rule_for(root.screen)) + 8
    margins.right: 8

    implicitWidth: 400
    implicitHeight: column.implicitHeight

    mask: Region { item: column }

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 8
        focus: true

        Keys.onPressed: event => root.handle_key(event)

        Repeater {
            // Ids, not entries: an array model snapshots copies of its objects. Each change still rebuilds the cards.
            model: root.visible_toasts.map(e => e.id)

            NotificationToastCard {
                id: toast_card
                Layout.fillWidth: true
                required property var modelData
                entry: root.visible_toasts.find(e => e.id === toast_card.modelData) || null
                selected: NotificationState.toast_focus && toast_card.modelData === NotificationState.toast_selected_id
                focused_action: toast_card.selected ? NotificationState.toast_action : -1
            }
        }
    }
}
