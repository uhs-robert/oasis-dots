// home/quickshell/.config/quickshell/services/CalendarState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Reads the calendar cache that calendar-sync writes; the bar never talks to the network. With no cache file
// nothing is configured: no events, no timer, and every surface that reads this draws nothing.
Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/calendar/events.json"
    // The chip shows this many minutes before a meeting starts.
    readonly property int chip_window_minutes: 15

    // True once a cache file has been read, even an empty one.
    property bool configured: false
    // Set while calendar-sync's error.json exists; the events are then the last good copy and may be stale.
    property string error: ""
    property double updated_ms: 0
    // Sorted by start; each has start_ms, end_ms and a day_keys list.
    property var events: []
    // "YYYY-MM-DD" -> that day's events.
    property var day_index: ({})

    // A day asked for over IPC or by a voice command; the clock popup takes it when it opens and clears it.
    property string requested_day: ""

    property double now_ms: Date.now()

    function refresh() {
        file.reload();
    }

    function day_key(date) {
        return date.getFullYear() + "-" + (date.getMonth() < 9 ? "0" : "") + (date.getMonth() + 1) + "-" + (date.getDate() < 10 ? "0" : "") + date.getDate();
    }

    // "YYYY-MM-DD" as a local date, or null when it is not a real day.
    function parse_day(text) {
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text || "");
        if (!m) return null;
        const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
        return root.day_key(d) === text ? d : null;
    }

    // Date.parse reads a bare date as UTC; an all-day event belongs to the local day it names.
    function parse_time(text) {
        const d = root.parse_day(String(text || "").slice(0, 10));
        return d && String(text).length === 10 ? d.getTime() : Date.parse(text);
    }

    function normalize(raw) {
        const out = [];
        for (const e of raw) {
            if (!e || e.status === "cancelled") continue;
            const start_ms = root.parse_time(e.start);
            if (isNaN(start_ms)) continue;
            const all_day = e.all_day === true;
            let end_ms = root.parse_time(e.end);
            // Zero-length events still occupy their start day; an all-day end is the exclusive next day.
            if (isNaN(end_ms) || end_ms <= start_ms) end_ms = all_day ? start_ms + 86400000 : start_ms;
            out.push({
                uid: e.uid || "",
                title: e.title || "(no title)",
                start_ms: start_ms,
                end_ms: end_ms,
                all_day: all_day,
                location: e.location || "",
                meet_url: e.meet_url || "",
                event_url: e.event_url || "",
                status: e.status || "confirmed"
            });
        }
        out.sort((a, b) => a.start_ms - b.start_ms || a.title.localeCompare(b.title));
        return out;
    }

    function build_index(list) {
        const index = {};
        for (const e of list) {
            const day = new Date(e.start_ms);
            day.setHours(0, 0, 0, 0);
            // The end instant is exclusive, so an event ending at midnight stays on the earlier day.
            do {
                const key = root.day_key(day);
                (index[key] = index[key] || []).push(e);
                day.setDate(day.getDate() + 1);
            } while (day.getTime() < e.end_ms);
        }
        for (const key in index) index[key].sort((a, b) => Number(b.all_day) - Number(a.all_day) || a.start_ms - b.start_ms);
        return index;
    }

    function events_on(date) {
        return root.day_index[root.day_key(date)] || [];
    }

    function has_events(date) {
        return root.events_on(date).length > 0;
    }

    function is_live(e) {
        return !e.all_day && e.start_ms <= root.now_ms && root.now_ms < e.end_ms;
    }

    // All-day events never count as meetings, so they neither fill the chip nor light the dot.
    readonly property var current_event: root.events.find(e => root.is_live(e)) || null
    readonly property bool in_meeting: root.current_event !== null

    readonly property var next_event_today: {
        const midnight = new Date(root.now_ms);
        midnight.setHours(24, 0, 0, 0);
        return root.events.find(e => !e.all_day && e.start_ms > root.now_ms && e.start_ms < midnight.getTime()) || null;
    }

    readonly property int minutes_until_next: root.next_event_today ? Math.ceil((root.next_event_today.start_ms - root.now_ms) / 60000) : -1

    FileView {
        id: file
        path: root.path
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                const list = root.normalize(Array.isArray(data.events) ? data.events : []);
                root.events = list;
                root.day_index = root.build_index(list);
                root.updated_ms = Date.parse(data.updated) || 0;
                root.configured = true;
            } catch (e) {
                // A half-written or broken file keeps the last good events.
                console.warn("CalendarState: invalid events.json (" + e + ")");
            }
        }
        onLoadFailed: {
            root.configured = false;
            root.events = [];
            root.day_index = {};
        }
    }

    FileView {
        path: root.path.replace(/events\.json$/, "error.json")
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let message = "";
            try {
                message = String(JSON.parse(text()).error || "");
            } catch (e) {}
            root.error = message || "sync failed";
        }
        onLoadFailed: root.error = ""
    }

    SystemClock {
        id: minute_clock
        enabled: root.configured
        precision: SystemClock.Minutes
        onDateChanged: root.now_ms = date.getTime()
    }

    onConfiguredChanged: root.now_ms = Date.now()
}
