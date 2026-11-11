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

function matches_track(tab, track_title, track_url) {
    var url = squashed(track_url);
    if (url !== "" && squashed(tab.url) === url) return true;
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
// are the candidates and the one matching the MPRIS track wins, else the most recently used one. With no audible tab,
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
    var matched = (by_audio ? audible : tabs).filter(function (t) { return matches_track(t, track_title, track_url); });
    if (matched.length > 0) return newest(matched);
    return by_audio ? newest(audible) : null;
}
