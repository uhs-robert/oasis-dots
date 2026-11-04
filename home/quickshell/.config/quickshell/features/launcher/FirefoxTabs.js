.pragma library

// The Firefox tabs picker's reading of voxcmd's extension host (FirefoxTabsProvider.qml), kept here so node can test it:
// replies from `firefox-tab request`, tab order, the window filter and thumbnail sources.

// One reply line: { state: "ok" | "unavailable" | "error", result, error }. No output at all means firefox-tab is
// missing or crashed, which is as unreachable as a missing socket.
function parse_reply(text) {
    var reply = null;
    try {
        reply = JSON.parse(text || "");
    } catch (e) {
        reply = null;
    }
    if (!reply || typeof reply !== "object") return { state: "unavailable", result: null, error: "no answer from firefox-tab" };
    if (reply.ok === true) return { state: "ok", result: reply.result, error: "" };
    return { state: reply.unavailable === true ? "unavailable" : "error", result: null, error: String(reply.error || "unknown error") };
}

// "example.com" from "https://www.example.com:8080/a?b"; a URL with no host keeps its scheme ("about:config", "file").
function short_host(url) {
    var u = String(url || "");
    var m = /^[a-z][a-z0-9+.-]*:\/\/(?:[^\/?#@]*@)?([^\/?#:]*)/i.exec(u);
    if (m && m[1] !== "") return m[1].replace(/^www\./i, "");
    var scheme = /^([a-z][a-z0-9+.-]*):/i.exec(u);
    if (!scheme) return u;
    return scheme[1].toLowerCase() === "about" ? u.split(/[?#]/)[0] : scheme[1].toLowerCase();
}

function number_or(value, fallback) {
    return typeof value === "number" && isFinite(value) ? value : fallback;
}

function text_or_empty(value) {
    return typeof value === "string" ? value : "";
}

// A picker item from one listed tab, or null for one the picker never shows: malformed, hidden, or private (the
// extension cannot see private windows, so one listed anyway is not shown either).
function tab_item(tab) {
    if (!tab || typeof tab !== "object" || typeof tab.tab_id !== "number" || typeof tab.window_id !== "number") return null;
    if (tab.hidden === true || tab.incognito === true) return null;
    var url = text_or_empty(tab.url);
    var host = short_host(url);
    return {
        id: String(tab.tab_id),
        tab_id: tab.tab_id,
        window_id: tab.window_id,
        label: text_or_empty(tab.title) || url,
        description: url,
        keywords: host !== "" ? [host] : [],
        url: url,
        host: host,
        active: tab.active === true,
        discarded: tab.discarded === true,
        pinned: tab.pinned === true,
        last_accessed: number_or(tab.last_accessed, 0),
        fav_icon_url: text_or_empty(tab.fav_icon_url),
        thumbnail: text_or_empty(tab.thumbnail),
        thumbnail_at: number_or(tab.thumbnail_at, 0)
    };
}

// The shown tabs, most recently used first: the focused window's active tab is the newest, so it leads.
function items_of(result) {
    if (!Array.isArray(result)) return [];
    var out = [];
    for (var i = 0; i < result.length; i++) {
        var item = tab_item(result[i]);
        if (item) out.push(item);
    }
    return out.sort(function (a, b) {
        return b.last_accessed - a.last_accessed || (b.active ? 1 : 0) - (a.active ? 1 : 0) || a.tab_id - b.tab_id;
    });
}

// Window ids in the order their first tab appears, so the window in use is window 1.
function windows_of(items) {
    var out = [];
    for (var i = 0; i < items.length; i++) if (out.indexOf(items[i].window_id) < 0) out.push(items[i].window_id);
    return out;
}

// `f`: all, then each window in turn, then all again. A window that has gone (its last tab closed) also goes back to all.
function cycled_filter(filter, windows) {
    if (filter === "all") return windows.length > 0 ? windows[0] : "all";
    var i = windows.indexOf(filter);
    return i >= 0 && i + 1 < windows.length ? windows[i + 1] : "all";
}

function kept_by_filter(item, filter) {
    return filter === "all" || item.window_id === filter;
}

// The search bar corner: "ALL", or the window's place among the open ones ("WINDOW 2/3").
function filter_label(filter, windows) {
    var i = windows.indexOf(filter);
    return filter === "all" || i < 0 ? "ALL" : "WINDOW " + (i + 1) + "/" + windows.length;
}

// tab id -> { thumbnail, thumbnail_at } from a `capture` result over the old map; a failed capture keeps the old image.
function merged_thumbs(thumbs, captures) {
    var next = {};
    for (var k in thumbs) next[k] = thumbs[k];
    if (!Array.isArray(captures)) return next;
    for (var i = 0; i < captures.length; i++) {
        var c = captures[i];
        if (!c || c.ok !== true || typeof c.tab_id !== "number" || typeof c.thumbnail !== "string" || c.thumbnail === "") continue;
        next[String(c.tab_id)] = { thumbnail: c.thumbnail, thumbnail_at: number_or(c.thumbnail_at, 0) };
    }
    return next;
}

// The newer of the image the list named and a capture since.
function thumb_of(item, thumbs) {
    var captured = thumbs[item.id];
    if (captured && captured.thumbnail_at >= item.thumbnail_at) return captured;
    return { thumbnail: item.thumbnail, thumbnail_at: item.thumbnail_at };
}

// A file URL for the image, or "". The host rewrites a tab's image at the same path, so the capture time rides along
// as a query: a new time is a new URL, which the Image loads afresh instead of reusing what it cached.
function thumbnail_source(thumb) {
    if (!thumb || typeof thumb.thumbnail !== "string" || thumb.thumbnail.charAt(0) !== "/") return "";
    return "file://" + thumb.thumbnail.split("/").map(encodeURIComponent).join("/") + "?at=" + number_or(thumb.thumbnail_at, 0);
}

// Only icons that need no network: Firefox hands most favicons over as data: URLs. An http one would have the bar
// fetch from the site, so it gets the generic glyph instead.
function favicon_source(url) {
    var u = String(url || "");
    return /^data:image\//i.test(u) || /^file:\/\//i.test(u) ? u : "";
}

// Tab ids for `capture`, a few per request so images swap in as they come rather than all at the end. Unloaded tabs
// cannot be captured, so they keep their cached image.
function capture_batches(items, size) {
    var ids = [];
    for (var i = 0; i < items.length; i++) if (!items[i].discarded) ids.push(items[i].tab_id);
    var out = [];
    var n = Math.max(1, size);
    for (var j = 0; j < ids.length; j += n) out.push(ids.slice(j, j + n));
    return out;
}
