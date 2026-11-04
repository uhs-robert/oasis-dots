.pragma library

// Searchable entries for Hyprland windows, shared by the overview's search and the windows picker so both rank a
// query the same way. Pure data in and out: WindowState.entries() reads the toplevels and hands each one here.

// Drops the app name a title ends with ("notes - Mozilla Firefox" on firefox) and Firefox's private-window prefix.
function clean_title(title, short_class) {
    let t = title || "";
    if (short_class.toLowerCase() === "firefox") t = t.replace(/^XXX\s*/, "");
    const m = /\s+[—-]\s+([^—-]+)$/.exec(t);
    const app = short_class.toLowerCase();
    return m && app !== "" && m[1].trim().toLowerCase().split(/\s+/).pop() === app ? t.slice(0, m.index) : t;
}

// `win` is { address, title, cls, initial_class, short_class, ws_name, ws_id, monitor }. The short class is the label,
// so Fuzzy ranks a class match above a title or workspace one.
function entry_of(win, recency) {
    const title = clean_title(win.title, win.short_class);
    return {
        id: win.address,
        address: win.address,
        recency: recency,
        label: win.short_class || "window",
        title: title,
        ws_name: win.ws_name,
        ws_id: win.ws_id,
        monitor: win.monitor || "",
        place: win.ws_name.replace(/^special:/, "special "),
        description: win.ws_name + " · " + title,
        keywords: [win.cls || "", win.initial_class || "", win.ws_name, win.title || ""]
    };
}

// Alt+Tab: with the focused window first, start on the one before it.
function previous_index(entries, active_address) {
    return entries.length >= 2 && entries[0].address === active_address ? 1 : 0;
}

// The windows picker's `f`: every window, the focused monitor's, then the focused workspace's.
var filters = ["all", "monitor", "workspace"];

function cycled_filter(filter) {
    return filters[(filters.indexOf(filter) + 1) % filters.length];
}

// `here` is { monitor, ws_id }, read when the picker opens.
function kept_by_filter(entry, filter, here) {
    if (filter === "monitor") return entry.monitor === here.monitor;
    if (filter === "workspace") return entry.ws_id === here.ws_id;
    return true;
}

function filter_label(filter) {
    return filter === "monitor" ? "MONITOR" : filter === "workspace" ? "WORKSPACE" : "ALL";
}
