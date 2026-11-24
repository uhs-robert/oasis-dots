.pragma library

// The voxtype history picker's parsing, day groups and filter (`f`), kept here so node can test it.

var filters = ["delivered", "all"];
var filter_labels = { delivered: "", all: "ALL" };
var day_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
var month_names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function cycled_filter(filter) {
    var i = filters.indexOf(filter);
    return filters[(i + 1) % filters.length];
}

// "delivered" also keeps an entry with no outcome, so an older voxtype that never wrote one still lists.
function kept_by_filter(entry, filter) {
    return filter === "all" || !entry.outcome || entry.outcome === "delivered";
}

// The text `voxtype history copy` and `paste` send: the correction, else the output, else what the engine heard.
function entry_text(raw) {
    return raw.correction || raw.text || raw.raw_text || "";
}

function pad2(n) {
    return n < 10 ? "0" + n : String(n);
}

// The local calendar day of `date`, as "YYYY-MM-DD".
function day_key(date) {
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate());
}

// "Today", "Yesterday", a weekday within the week, then "Nov 12".
function day_title(key, now) {
    var parts = key.split("-");
    var day = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    var today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    var days_ago = Math.round((today - day) / 86400000);
    if (days_ago === 0) return "Today";
    if (days_ago === 1) return "Yesterday";
    if (days_ago > 1 && days_ago < 7) return day_names[day.getDay()];
    return month_names[day.getMonth()] + " " + day.getDate();
}

// A day header: "TODAY · 4 DICTATIONS".
function group_title(key, shown_count, now) {
    var head = key === "" ? "Undated" : day_title(key, now);
    return head.toUpperCase() + " · " + shown_count + (shown_count === 1 ? " DICTATION" : " DICTATIONS");
}

// `voxtype history list --json` output -> { state, paused, entries }, entries newest first. state is "ok", "off"
// (history disabled), "missing" (no voxtype) or "error" (output that is not the expected JSON).
function parse(text) {
    if (text.trim() === "missing") return { state: "missing", paused: false, entries: [] };
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return { state: "error", paused: false, entries: [] };
    }
    if (!data || !Array.isArray(data.entries)) return { state: "error", paused: false, entries: [] };
    var entries = [];
    for (var i = 0; i < data.entries.length; i++) {
        var raw = data.entries[i];
        var full = entry_text(raw);
        if (!raw.id || full === "") continue;
        var when = new Date(raw.ts_start || raw.ts_end || "");
        var valid = !isNaN(when.getTime());
        entries.push({
            id: raw.id,
            label: full.replace(/\s+/g, " ").trim(),
            text: full,
            app: raw.app || "",
            outcome: raw.outcome || "",
            day: valid ? day_key(when) : "",
            time: valid ? pad2(when.getHours()) + ":" + pad2(when.getMinutes()) : "",
            keywords: raw.app ? [raw.app] : []
        });
    }
    return { state: data.enabled === false && entries.length === 0 ? "off" : "ok", paused: !!data.paused, entries: entries };
}
