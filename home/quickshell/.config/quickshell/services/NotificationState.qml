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
    // Toast timers by entry id; kept off the entries so model rows never hold a Timer.
    property var timers: ({})
    readonly property int unread: history.filter(e => !e.read).length

    readonly property int timeout_normal_ms: 5000
    readonly property int timeout_low_ms: 3000
    readonly property int max_visible_toasts: 5
    readonly property var visible_toasts: root.toasts.slice(0, root.max_visible_toasts)

    // Keyboard focus on the toast stack; the selection is tracked by entry id.
    property bool toast_focus: false
    property var toast_selected_id: null
    property int toast_index: 0
    // -1 is the toast body; 0.. are the selected toast's action buttons.
    property int toast_action: -1

    onToastsChanged: root.sync_toast_focus()

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
        const entry = { id: n.id, notification: n, time: Date.now(), read: read, paused: false, on_closed: null };
        entry.on_closed = () => root.remove_entry(entry);
        n.closed.connect(entry.on_closed);
        return entry;
    }

    // Only visible toasts count down; queued ones wait for a slot so a burst never expires unseen.
    function sync_timers() {
        root.toasts.forEach((entry, i) => {
            const timer = root.timers[entry.id];
            if (i >= root.max_visible_toasts) {
                if (timer) timer.stop();
            } else if (!timer) {
                root.start_timeout(entry, entry.notification);
            } else if (!timer.running && !entry.paused && !root.toast_focus) {
                timer.restart();
            }
        });
    }

    // Maps any entry-shaped value (e.g. from a delegate) back to the live entry with its id.
    function resolve(entry) {
        if (!entry) return null;
        return root.toasts.find(e => e.id === entry.id) || root.history.find(e => e.id === entry.id) || null;
    }

    function stop_all_timers(entries) {
        for (const entry of entries) {
            const timer = root.timers[entry.id];
            if (timer) timer.stop();
        }
    }

    function start_timeout(entry, n) {
        // expireTimeout is in ms: 0 means never, negative means the server default.
        const fallback = n.urgency === NotificationUrgency.Critical ? 0 : n.urgency === NotificationUrgency.Low ? root.timeout_low_ms : root.timeout_normal_ms;
        const ms = n.expireTimeout >= 0 ? n.expireTimeout : fallback;
        if (ms <= 0) return;
        const id = entry.id;
        const timer = timer_component.createObject(root, { interval: ms });
        timer.triggered.connect(() => {
            if (root.timers[id] !== timer) return;
            const in_history = root.history.some(e => e.id === id);
            root.hide_toast(entry);
            if (!in_history && entry.notification) entry.notification.expire();
        });
        root.timers[id] = timer;
        if (!root.toast_focus) timer.start();
    }

    function stop_timer(id) {
        const timer = root.timers[id];
        if (!timer) return;
        delete root.timers[id];
        timer.stop();
        timer.destroy();
    }

    // Drops an entry from both lists, e.g. when the app itself closes/expires it.
    function remove_entry(entry) {
        const live = root.resolve(entry);
        if (!live) {
            if (entry) root.disconnect_entry(entry);
            return;
        }
        root.toasts = root.toasts.filter(e => e.id !== live.id);
        root.history = root.history.filter(e => e.id !== live.id);
        root.stop_timer(live.id);
        root.disconnect_entry(live);
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
        const live = root.resolve(entry);
        if (!live) return;
        if (live.notification) live.notification.dismiss();
        root.remove_entry(live);
    }

    function clear_all() {
        const all = root.history.concat(root.toasts.filter(e => !root.history.includes(e)));
        for (const entry of all) root.dismiss(entry);
    }

    function hide_toast(entry) {
        if (!entry) return;
        const id = entry.id;
        root.toasts = root.toasts.filter(e => e.id !== id);
        root.stop_timer(id);
        root.sync_timers();
    }

    function hide_latest_toast() {
        if (root.toasts.length > 0) root.hide_toast(root.toasts[0]);
    }

    function hide_all_toasts() {
        for (const entry of root.toasts.slice()) root.hide_toast(entry);
    }

    function pause_toast(entry) {
        const live = root.resolve(entry);
        if (!live) return;
        live.paused = true;
        root.stop_all_timers([live]);
    }

    function resume_toast(entry) {
        const live = root.resolve(entry);
        if (!live) return;
        live.paused = false;
        const timer = root.timers[live.id];
        if (timer && !root.toast_focus) timer.restart();
    }

    function focus_toast(direction) {
        if (root.visible_toasts.length === 0) return false;
        if (!root.toast_focus) {
            root.toast_focus = true;
            root.stop_all_timers(root.toasts);
            root.select_toast(0);
        } else {
            root.move_toast(direction === "prev" ? -1 : 1);
        }
        return true;
    }

    function leave_toast_focus() {
        if (!root.toast_focus) return;
        root.toast_focus = false;
        root.toast_action = -1;
        root.sync_timers();
    }

    function select_toast(index) {
        const list = root.toasts.slice(0, root.max_visible_toasts);
        if (index < 0 || index >= list.length) return;
        root.toast_index = index;
        root.toast_selected_id = list[index].id;
        root.toast_action = -1;
    }

    function move_toast(delta) {
        const count = Math.min(root.toasts.length, root.max_visible_toasts);
        root.select_toast(Math.max(0, Math.min(count - 1, root.toast_index + delta)));
    }

    function selected_toast() {
        return root.toasts.slice(0, root.max_visible_toasts).find(e => e.id === root.toast_selected_id) || null;
    }

    function move_toast_action(delta) {
        const entry = root.selected_toast();
        const count = entry ? root.actions_of(entry).length : 0;
        root.toast_action = Math.max(-1, Math.min(count - 1, root.toast_action + delta));
    }

    function invoke_selected_toast() {
        const entry = root.selected_toast();
        const actions = entry ? root.actions_of(entry) : [];
        const action = actions[root.toast_action] || null;
        root.leave_toast_focus();
        if (!entry) return;
        if (action) root.invoke_action(entry, action);
        else root.invoke_default(entry);
    }

    function dismiss_selected_toast() {
        const entry = root.selected_toast();
        if (entry) root.dismiss(entry);
    }

    // Keeps the selection on its entry as toasts come and go, falling back to the same slot.
    function sync_toast_focus() {
        if (!root.toast_focus) return;
        const list = root.toasts.slice(0, root.max_visible_toasts);
        if (list.length === 0) {
            root.leave_toast_focus();
            return;
        }
        root.stop_all_timers(list);
        const idx = list.findIndex(e => e.id === root.toast_selected_id);
        if (idx >= 0) root.toast_index = idx;
        else root.select_toast(Math.min(root.toast_index, list.length - 1));
    }

    function actions_of(entry) {
        const all = entry && entry.notification && entry.notification.actions ? entry.notification.actions : [];
        const list = [];
        for (let i = 0; i < all.length; i++) if (all[i].identifier !== "default") list.push(all[i]);
        return list;
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
        entry = root.resolve(entry) || entry;
        const n = entry.notification;
        const action = root.find_default_action(n);
        if (n) root.focus_app(n.desktopEntry, n.appName);
        if (action) root.invoke_action(entry, action);
        else root.hide_toast(entry);
    }

    // Apps can't raise themselves without an activation token, so focus the sender's most recent window by class.
    function focus_app(desktop_entry, app_name) {
        const filter = '([$d, $n] | map(ascii_downcase | select(. != ""))) as $keys'
            + ' | [.[] | select(.class | ascii_downcase as $c | any($keys[]; . as $k | $c == $k or ($c | endswith("." + $k)) or ($c | contains($k))))]'
            + ' | sort_by(.focusHistoryID) | .[0].address // empty';
        const script = 'a=$(hyprctl clients -j | jq -r --arg d "$1" --arg n "$2" "$3"); [ -n "$a" ] || exit 0; '
            + 'hyprctl dispatch "hl.dsp.focus({ window = \'address:$a\' })" >/dev/null 2>&1 || hyprctl dispatch focuswindow "address:$a" >/dev/null';
        Quickshell.execDetached(["sh", "-c", script, "sh", desktop_entry || "", app_name || "", filter]);
    }

    // Per spec an invoked action closes the notification unless the app marked it resident.
    function invoke_action(entry, action) {
        entry = root.resolve(entry) || entry;
        action.invoke();
        if (entry.notification && entry.notification.resident) root.hide_toast(entry);
        else root.dismiss(entry);
    }

    function mark_read() {
        for (const e of root.history) e.read = true;
        root.history = root.history.slice();
    }

    // Meeting invites open with a ~:~:~ rule; lines made only of punctuation carry nothing.
    function clean_body(text) {
        if (!text) return "";
        return text.split(/<br\s*\/?>|\n/).filter(l => !/^[\s\-~:_=*#.·|]{6,}$/.test(l)).join("<br>").replace(/^(\s|<br>)+|(\s|<br>)+$/g, "");
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
