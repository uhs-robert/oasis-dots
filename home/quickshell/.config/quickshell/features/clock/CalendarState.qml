pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Reads the calendar cache that calendar-sync writes; the bar never talks to the network. With no cache file
// nothing is configured: no events, no timer, and every surface that reads this draws nothing.
Singleton {
    id: root

    readonly property string path: Paths.xdg("XDG_CACHE_HOME", "/.cache") + "/calendar/events.json"
    // The chip shows this many minutes before a meeting starts.
    readonly property int chip_window_minutes: 15
    // Timed events longer than this are out-of-office or conference blocks, not meetings to join.
    readonly property double max_meeting_ms: 12 * 3600000

    // True once a cache file has been read, even an empty one.
    readonly property bool configured: cache.values.configured
    // calendar-sync's error.json: the events are then the last good copy and may be stale. An error older than the
    // cache's `updated` is left over from before a good sync, so it is ignored.
    readonly property string error_message: error_cache.values.message
    readonly property double error_at_ms: error_cache.values.at_ms
    readonly property string error: root.error_message !== "" && (!root.configured || root.error_at_ms >= root.updated_ms) ? root.error_message : ""
    readonly property double updated_ms: cache.values.updated_ms
    // The span calendar-sync fetched, start inclusive, end exclusive; 0 when an older cache does not say.
    readonly property double window_start_ms: cache.values.window_start_ms
    readonly property double window_end_ms: cache.values.window_end_ms
    readonly property bool has_window: root.window_start_ms > 0 && root.window_end_ms > root.window_start_ms
    // Sorted by start; each has start_ms, end_ms and a day_keys list.
    readonly property var events: cache.values.events
    // "YYYY-MM-DD" -> that day's events.
    readonly property var day_index: cache.values.day_index

    // A day asked for over IPC or by a voice command; the clock popup takes it when it opens and clears it.
    property string requested_day: ""

    property double now_ms: Date.now()

    // Reloads both files by hand too: a watch cannot report a file whose folder did not exist when it started.
    function refresh() {
        cache.rearm();
        error_cache.rearm();
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

    // Invites are written by strangers: one line, no stray whitespace.
    function one_line(text) {
        return String(text || "").replace(/\s+/g, " ").trim();
    }

    function normalize(raw) {
        const out = [];
        for (const e of raw) {
            if (!e || e.status === "cancelled") continue;
            const all_day = e.all_day === true;
            // An all-day event is a calendar date, not an instant: read its date part as local midnight, so a cache
            // written in one zone does not shift the event onto the day before after travel.
            const read = text => all_day ? root.parse_time(String(text || "").slice(0, 10)) : root.parse_time(text);
            const start_ms = read(e.start);
            if (isNaN(start_ms)) continue;
            let end_ms = read(e.end);
            // Zero-length events still occupy their start day; an all-day end is the exclusive next day.
            if (isNaN(end_ms) || end_ms <= start_ms) end_ms = all_day ? start_ms + 86400000 : start_ms;
            out.push({
                uid: e.uid || "",
                title: root.one_line(e.title) || "(no title)",
                start_ms: start_ms,
                end_ms: end_ms,
                all_day: all_day,
                location: root.one_line(e.location),
                organizer: root.one_line(e.organizer),
                guests: Array.isArray(e.attendees) ? e.attendees.length : 0,
                join_url: e.join_url || "",
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

    // Whether any part of the day lies inside the synced window; every day counts when the cache has none.
    function is_synced(date) {
        if (!root.has_window) return true;
        const first = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
        const next = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime();
        return next > root.window_start_ms && first < root.window_end_ms;
    }

    // Days that have events, oldest first.
    readonly property var event_days: Object.keys(root.day_index).filter(k => root.is_synced(root.parse_day(k))).sort()

    // The nearest day with events after (step 1) or before (step -1) `date`, searching the whole cache; null when there is none.
    function adjacent_event_day(date, step) {
        const here = root.day_key(date);
        const key = step > 0 ? root.event_days.find(k => k > here) : root.event_days.slice().reverse().find(k => k < here);
        return key ? root.parse_day(key) : null;
    }

    function events_on(date) {
        return root.day_index[root.day_key(date)] || [];
    }

    function has_events(date) {
        return root.events_on(date).length > 0;
    }

    function is_meeting(e) {
        return !e.all_day && e.end_ms - e.start_ms <= root.max_meeting_ms;
    }

    function is_live(e) {
        return root.is_meeting(e) && e.start_ms <= root.now_ms && root.now_ms < e.end_ms;
    }

    // All-day events and day-long blocks never count as meetings, so they neither fill the chip nor light the dot.
    readonly property var current_event: root.events.find(e => root.is_live(e)) || null
    readonly property bool in_meeting: root.current_event !== null

    readonly property var next_event_today: {
        const midnight = new Date(root.now_ms);
        midnight.setHours(24, 0, 0, 0);
        return root.events.find(e => root.is_meeting(e) && e.start_ms > root.now_ms && e.start_ms < midnight.getTime()) || null;
    }

    readonly property int minutes_until_next: root.next_event_today ? root.minutes_to(root.next_event_today) : -1

    function minutes_to(e) {
        return Math.ceil((e.start_ms - root.now_ms) / 60000);
    }

    // The chip looks a fixed time ahead, so it carries across midnight where next_event_today stops.
    readonly property var chip_event: root.events.find(e => root.is_meeting(e) && e.start_ms > root.now_ms && e.start_ms <= root.now_ms + root.chip_window_minutes * 60000) || null

    // A missing file is the defaults: nothing configured. A half-written or broken one is too, until the next good sync
    // (calendar-sync replaces the file atomically).
    JsonStore {
        id: cache
        path: root.path
        read_only: true
        defaults: ({ configured: false, events: [], day_index: {}, updated_ms: 0, window_start_ms: 0, window_end_ms: 0 })
        validate: raw => {
            const list = root.normalize(Array.isArray(raw.events) ? raw.events : []);
            return {
                configured: true,
                events: list,
                day_index: root.build_index(list),
                updated_ms: Date.parse(raw.updated) || 0,
                window_start_ms: Date.parse(raw.window_start) || 0,
                window_end_ms: Date.parse(raw.window_end) || 0
            };
        }
    }

    JsonStore {
        id: error_cache
        path: root.path.replace(/events\.json$/, "error.json")
        read_only: true
        defaults: ({ message: "", at_ms: 0 })
        validate: raw => {
            const at_ms = Date.parse(raw.at);
            // Without a readable time the error counts as current.
            return { message: String(raw.error || "") || "sync failed", at_ms: isNaN(at_ms) ? Number.MAX_VALUE : at_ms };
        }
    }

    SystemClock {
        id: minute_clock
        enabled: root.configured
        precision: SystemClock.Minutes
        onDateChanged: root.now_ms = date.getTime()
    }

    onConfiguredChanged: root.now_ms = Date.now()
}
