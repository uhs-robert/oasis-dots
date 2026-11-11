.pragma library

// The Firefox tabs picker's reading of DesertFox's bridge (FirefoxTabsProvider.qml), kept here so node can test it:
// replies from `firefox-tab request`, tab order and the sort, window numbers and headers, the window filter and
// thumbnail sources.

// One reply line from `firefox-tab request`: { state: "ok" | "unavailable" | "sharing_off" | "error", fields, error }.
// `fields` is the bridge's reply (its named fields, `tabs` or `results`) and `error` its message. No output at all means
// firefox-tab is missing or crashed, which is as unreachable as a missing socket. "sharing_off" is a bridge that is up
// while `bridge_share_tabs` is off in DesertFox.
function parse_reply(text) {
    var reply = null;
    try {
        reply = JSON.parse(text || "");
    } catch (e) {
        reply = null;
    }
    if (!reply || typeof reply !== "object") return { state: "unavailable", fields: null, error: "no answer from firefox-tab" };
    if (reply.ok === true) return { state: "ok", fields: reply, error: "" };
    var state = reply.sharing_off === true ? "sharing_off" : reply.unavailable === true ? "unavailable" : "error";
    return { state: state, fields: null, error: String(reply.message || "unknown error") };
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

// A picker item from one listed tab, or null for one the picker never shows: malformed or hidden. A private window's
// tabs never come from the bridge.
function tab_item(tab) {
    if (!tab || typeof tab !== "object" || typeof tab.tab_id !== "number" || typeof tab.window_id !== "number") return null;
    if (tab.hidden === true) return null;
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

// The shown tabs in the order the bridge lists them: Firefox's `tabs.query` gives each window's tabs in tab-bar order.
function items_of(result) {
    if (!Array.isArray(result)) return [];
    var out = [];
    for (var i = 0; i < result.length; i++) {
        var item = tab_item(result[i]);
        if (item) out.push(item);
    }
    return out;
}

// Most recently used first: the focused window's active tab is the newest, so it leads.
function recent_first(items) {
    return items.slice().sort(function (a, b) {
        return b.last_accessed - a.last_accessed || (b.active ? 1 : 0) - (a.active ? 1 : 0) || a.tab_id - b.tab_id;
    });
}

// Window ids ascending, which is the order Firefox made them in: window N is the Nth of them, in the filter, the
// headers and the badges alike.
function windows_of(items) {
    var out = [];
    for (var i = 0; i < items.length; i++) if (out.indexOf(items[i].window_id) < 0) out.push(items[i].window_id);
    return out.sort(function (a, b) {
        return a - b;
    });
}

function window_number(window_id, windows) {
    return windows.indexOf(window_id) + 1;
}

// `s` flips the order: "tabs" groups by window in tab-bar order, "recent" is one list, most recently used first.
var sorts = ["tabs", "recent"];
var sort_labels = { tabs: "TAB ORDER", recent: "RECENT" };

function sort_of(name) {
    return sorts.indexOf(name) >= 0 ? name : sorts[0];
}

function cycled_sort(sort) {
    return sorts[(sorts.indexOf(sort_of(sort)) + 1) % sorts.length];
}

// The picker's items: the tabs the window filter keeps, each with its window's number, in the sort's order.
function arranged(items, sort, filter, windows) {
    var out = [];
    for (var i = 0; i < items.length; i++) {
        if (!kept_by_filter(items[i], filter)) continue;
        var item = Object.assign({}, items[i]);
        item.window_number = window_number(item.window_id, windows);
        out.push(item);
    }
    return sort_of(sort) === "recent" ? recent_first(out) : out;
}

// A window's header over the tabs of it that show: "WINDOW 1 · 14 TABS · " and the title of its active tab, which is
// found among all its tabs, so a search that hides the active one keeps the title.
function group_title(window_id, shown_count, items, windows) {
    var parts = ["WINDOW " + window_number(window_id, windows), shown_count + (shown_count === 1 ? " TAB" : " TABS")];
    for (var i = 0; i < items.length; i++) {
        if (items[i].window_id === window_id && items[i].active) {
            parts.push(items[i].label);
            break;
        }
    }
    return parts.join(" · ");
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

// tab id -> { thumbnail, thumbnail_at } from a `capture` reply's results over the old map; a failed capture keeps the old image.
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

// A file URL for the image, or "". The bridge rewrites a tab's image at the same path, so the capture time rides along
// as a query: a new time is a new URL, which the Image loads afresh instead of reusing what it cached.
function thumbnail_source(thumb) {
    if (!thumb || typeof thumb.thumbnail !== "string" || thumb.thumbnail.charAt(0) !== "/") return "";
    return "file://" + thumb.thumbnail.split("/").map(encodeURIComponent).join("/") + "?at=" + number_or(thumb.thumbnail_at, 0);
}

// Only icons that need no network. The bridge blanks a data: URL icon (a list of them would outgrow one message), and
// an http one would have the bar fetch from the site, so most tabs get the generic glyph.
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
