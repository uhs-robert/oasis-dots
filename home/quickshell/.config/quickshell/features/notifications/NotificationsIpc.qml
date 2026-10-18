import Quickshell.Io
import Quickshell.Services.Notifications
import qs.services
import qs.features.popups

IpcHandler {
    id: root
    target: "notifications"

    // Untyped, so IpcHandler does not expose it. notify-send --icon arrives as the image hint, which Quickshell turns into an image://icon/ URL; other image://
    // URLs are pixel data only the bar can draw.
    function icon_name_of(image) {
        const name = image.replace(/^image:\/\/icon\//, "");
        return name.startsWith("image:") ? "" : name;
    }

    function toggle_dnd(): void {
        NotificationState.toggle_dnd();
    }

    function get_dnd(): bool {
        return NotificationState.dnd;
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

    function focus_toast(direction: string): string {
        if (!NotificationState.toast_focus && NotificationState.visible_toasts.length > 0 && Popups.open_name !== "") Popups.close();
        return NotificationState.focus_toast(direction) ? "toast" : "none";
    }

    function fields_of(n) {
        return { app: n.appName, summary: n.summary, body: n.body, icon: n.appIcon || root.icon_name_of(n.image) };
    }

    function urgency_name_of(urgency) {
        return urgency === NotificationUrgency.Critical ? "critical" : urgency === NotificationUrgency.Low ? "low" : "normal";
    }

    // The newest history entry as {app, summary, body, icon}, or "" when the history is empty.
    function get_last(): string {
        const latest = NotificationState.history[0];
        if (!latest || !latest.notification) return "";
        return JSON.stringify(root.fields_of(latest.notification));
    }

    // The newest `count` history entries (all of them when count <= 0), newest first, only app's when app is not "":
    // a JSON array of get_last's fields plus time (ISO, UTC), urgency and read. Transient notifications never reach
    // the history, so this holds only the ones the bar keeps.
    function history(count: int, app: string): string {
        const matching = NotificationState.history.filter(e => e.notification && (app === "" || e.notification.appName === app));
        const newest = count > 0 ? matching.slice(0, count) : matching;
        return JSON.stringify(newest.map(root.history_fields_of));
    }

    function history_fields_of(entry) {
        const n = entry.notification;
        return Object.assign({ time: new Date(entry.time).toISOString() }, root.fields_of(n), { urgency: root.urgency_name_of(n.urgency), read: entry.read });
    }

    function has_toast(): bool {
        return NotificationState.visible_toasts.length > 0;
    }

    function open(): void {
        Popups.open("notifications", undefined);
    }

    function close(): void {
        Popups.close();
    }
}
