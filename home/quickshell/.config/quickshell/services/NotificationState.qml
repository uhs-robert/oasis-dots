// home/quickshell/.config/quickshell/services/NotificationState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// One shared notification server for every bar/popup/toast. Entries wrap a tracked
// Notification with the time it arrived; history and toasts are newest-first arrays.
Singleton {
    id: root

    property var history: []
    property var toasts: []
    property bool dnd: false
    readonly property int unread: history.filter(e => !e.read).length

    readonly property int timeout_normal_ms: 5000
    readonly property int timeout_low_ms: 3000
    readonly property int max_visible_toasts: 5

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: false
        bodyImagesSupported: true
        imageSupported: true
        actionsSupported: true

        onNotification: notification => root.handle_notification(notification)
    }

    Component {
        id: timer_component
        Timer { repeat: false }
    }

    function handle_notification(n) {
        const suppressed = root.dnd && n.urgency !== NotificationUrgency.Critical;
        if (n.transient && suppressed) return;
        n.tracked = true;
        // A replaces_id update arrives as a new generation with the same id.
        for (const old of root.history.concat(root.toasts).filter(e => e.id === n.id)) {
            if (old.notification && old.notification !== n) old.notification.tracked = false;
            root.remove_entry(old);
        }

        const entry = root.make_entry(n, false);
        if (!n.transient) root.history = [entry].concat(root.history);
        if (suppressed) return;
        root.toasts = [entry].concat(root.toasts);
        root.sync_timers();
    }

    function make_entry(n, read) {
        const entry = { id: n.id, notification: n, time: Date.now(), timer: null, read: read, on_closed: null };
        entry.on_closed = () => root.remove_entry(entry);
        n.closed.connect(entry.on_closed);
        return entry;
    }

    // Only visible toasts count down; queued ones wait for a slot so a burst never expires unseen.
    function sync_timers() {
        root.toasts.forEach((entry, i) => {
            if (i >= root.max_visible_toasts) {
                if (entry.timer) entry.timer.stop();
            } else if (!entry.timer) {
                root.start_timeout(entry, entry.notification);
            } else if (!entry.timer.running && !entry.paused) {
                entry.timer.restart();
            }
        });
    }

    function start_timeout(entry, n) {
        // expireTimeout is in ms: 0 means never, negative means the server default.
        const fallback = n.urgency === NotificationUrgency.Critical ? 0 : n.urgency === NotificationUrgency.Low ? root.timeout_low_ms : root.timeout_normal_ms;
        const ms = n.expireTimeout >= 0 ? n.expireTimeout : fallback;
        if (ms <= 0) return;
        const timer = timer_component.createObject(root, { interval: ms });
        timer.triggered.connect(() => {
            root.hide_toast(entry);
            if (!root.history.includes(entry) && entry.notification) entry.notification.expire();
        });
        entry.timer = timer;
        timer.start();
    }

    function stop_timer(entry) {
        if (!entry.timer) return;
        entry.timer.stop();
        entry.timer.destroy();
        entry.timer = null;
    }

    // Drops an entry from both lists, e.g. when the app itself closes/expires it.
    function remove_entry(entry) {
        root.toasts = root.toasts.filter(e => e !== entry);
        root.history = root.history.filter(e => e !== entry);
        root.stop_timer(entry);
        root.disconnect_entry(entry);
        root.sync_timers();
    }

    function disconnect_entry(entry) {
        if (!entry.on_closed || !entry.notification) return;
        try {
            entry.notification.closed.disconnect(entry.on_closed);
        } catch (e) {}
        entry.on_closed = null;
    }

    function dismiss(entry) {
        if (entry.notification) entry.notification.dismiss();
        root.remove_entry(entry);
    }

    function clear_all() {
        const all = root.history.concat(root.toasts.filter(e => !root.history.includes(e)));
        for (const entry of all) root.dismiss(entry);
    }

    function hide_toast(entry) {
        root.toasts = root.toasts.filter(e => e !== entry);
        root.stop_timer(entry);
        root.sync_timers();
    }

    function hide_latest_toast() {
        if (root.toasts.length > 0) root.hide_toast(root.toasts[0]);
    }

    function hide_all_toasts() {
        for (const entry of root.toasts.slice()) root.hide_toast(entry);
    }

    function pause_toast(entry) {
        entry.paused = true;
        if (entry.timer) entry.timer.stop();
    }

    function resume_toast(entry) {
        entry.paused = false;
        if (entry.timer) entry.timer.restart();
    }

    function toggle_dnd() {
        root.dnd = !root.dnd;
        root.save_state();
    }

    function find_default_action(n) {
        if (!n || !n.actions) return null;
        for (let i = 0; i < n.actions.length; i++) {
            if (n.actions[i].identifier === "default") return n.actions[i];
        }
        return null;
    }

    function invoke_default(entry) {
        const action = root.find_default_action(entry.notification);
        if (action) root.invoke_action(entry, action);
        else root.hide_toast(entry);
    }

    // Per spec an invoked action closes the notification unless the app marked it resident.
    function invoke_action(entry, action) {
        action.invoke();
        if (entry.notification && entry.notification.resident) root.hide_toast(entry);
        else root.dismiss(entry);
    }

    function mark_read() {
        for (const e of root.history) e.read = true;
        root.history = root.history.slice();
    }

    readonly property string state_dir: Quickshell.stateDir

    Process {
        id: ensure_state_dir
        command: ["mkdir", "-p", root.state_dir]
    }

    FileView {
        id: state_file
        path: root.state_dir + "/notifications.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.dnd = !!parsed.dnd;
            } catch (e) {
                console.warn("Notifications: invalid notifications.json (" + e + ")");
            }
        }
        onLoadFailed: error => {}
    }

    function save_state() {
        state_file.setText(JSON.stringify({ dnd: root.dnd }));
    }

    Component.onCompleted: {
        ensure_state_dir.running = true;
        state_file.reload();
        root.restore_tracked();
    }

    // Tracked notifications outlive this singleton on reload; drop its handlers so they don't pile up.
    Component.onDestruction: {
        for (const entry of root.history.concat(root.toasts)) root.disconnect_entry(entry);
    }

    // keepOnReload keeps the server's notifications across a qs reload, but this singleton's lists start empty.
    function restore_tracked() {
        const restored = [];
        for (const n of server.trackedNotifications.values.slice()) {
            if (n.transient) {
                n.expire();
                continue;
            }
            restored.push(root.make_entry(n, true));
        }
        root.history = restored.reverse().concat(root.history);
    }
}
