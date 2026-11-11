.pragma library

// The pure half of jumping from the media module to the Firefox tab behind it (MediaJumpState.qml).

// Whether an MPRIS player is Firefox. Same rule as DesertfoxState.js is_firefox_class, kept as a short copy because a
// `.pragma library` file cannot import a sibling feature cheaply. An empty desktop entry falls back to the bus name
// (`org.mpris.MediaPlayer2.firefox.instance_<pid>`).
function is_firefox_player(desktop_entry, dbus_name) {
    var entry = String(desktop_entry || "").toLowerCase();
    if (entry !== "") return entry.indexOf("firefox") === 0 || entry.indexOf("org.mozilla.firefox") === 0;
    return String(dbus_name || "").toLowerCase().indexOf(".firefox.") !== -1;
}

function squashed(text) {
    return String(text || "").replace(/\s+/g, " ").trim();
}

function url_matches(tab, track_url) {
    var url = squashed(track_url);
    return url !== "" && squashed(tab.url) === url;
}

function title_matches(tab, track_title) {
    var title = squashed(track_title);
    return title !== "" && squashed(tab.title).indexOf(title) !== -1;
}

function newest(tabs) {
    var best = tabs[0];
    for (var i = 1; i < tabs.length; i++) {
        if ((Number(tabs[i].last_accessed) || 0) >= (Number(best.last_accessed) || 0)) best = tabs[i];
    }
    return best;
}

// The `tabs` rows of the bridge's reply -> the row to switch to, or null. While the player plays, the audible tabs
// are the candidates and the one matching the MPRIS track (url first, then title) wins, else the most recently used one. With no audible tab,
// or a paused player (nothing is audible then), only a title or url match across every tab counts: guessing by recency
// would pick an unrelated tab.
function pick_tab(rows, track_title, track_url, playing) {
    var tabs = [];
    for (var i = 0; Array.isArray(rows) && i < rows.length; i++) {
        var row = rows[i];
        if (row && typeof row === "object" && typeof row.tab_id === "number" && row.hidden !== true) tabs.push(row);
    }
    var audible = tabs.filter(function (t) { return t.audible === true; });
    var by_audio = playing && audible.length > 0;
    var pool = by_audio ? audible : tabs;
    // An exact url is the track's identity, a title can repeat across tabs, so titles count only when no url matches.
    var by_url = pool.filter(function (t) { return url_matches(t, track_url); });
    if (by_url.length > 0) return newest(by_url);
    var by_title = pool.filter(function (t) { return title_matches(t, track_title); });
    if (by_title.length > 0) return newest(by_title);
    return by_audio ? newest(audible) : null;
}
