// home/quickshell/.config/quickshell/services/NotificationsIpc.qml
import Quickshell.Io

IpcHandler {
    target: "notifications"

    function toggle_dnd(): void {
        NotificationState.toggle_dnd();
    }

    function clear_all(): void {
        NotificationState.clear_all();
    }

    function dismiss_latest(): void {
        NotificationState.hide_latest_toast();
    }

    function dismiss_all(): void {
        NotificationState.hide_all_toasts();
    }

    function open(): void {
        Popups.open("notifications", undefined);
    }

    function close(): void {
        Popups.close();
    }
}
