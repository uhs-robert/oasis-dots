.pragma library

// Which tabs are making sound, from the DesertFox bridge's event stream (wire format: host/README.md in DesertFox).
// Pure, so a node test can run it. A state is { audible: [tab...], touched: {tab_id: true} }, `audible` oldest first, so
// the last entry is the tab to show. `touched` is the tabs an event named since the stream started: a one-time tab list
// taken at connect is older than any of those and must not overwrite them. `pending` holds the title and address of a
// tab that is not known to play yet, so a title change that beats the tab list is not lost when the list adds the tab.

var empty = { audible: [], touched: {}, pending: {} };

// A page that retitles many silent tabs must not grow `pending` without end before the list arrives.
var max_pending = 64;

function tab_of(fields) {
    return {
        tab_id: fields.tab_id,
        window_id: fields.window_id,
        title: String(fields.title || ""),
        url: String(fields.url || "")
    };
}

function without(list, tab_id) {
    return list.filter(t => t.tab_id !== tab_id);
}

function omit(map, tab_id) {
    const next = Object.assign({}, map);
    delete next[tab_id];
    return next;
}

function mark(touched, tab_id) {
    const next = Object.assign({}, touched);
    next[tab_id] = true;
    return next;
}

// One stream line as { kind: "ack" | "refused" | "event" | "junk", event? }. The first line of a stream is the ack or
// a refusal (the host's four subscriber places taken, or the rate limit).
function parse_line(text) {
    let line;
    try {
        line = JSON.parse(text);
    } catch (e) {
        return { kind: "junk" };
    }
    if (!line || typeof line !== "object") return { kind: "junk" };
    if (line.ok === true) return { kind: "ack" };
    if (line.ok === false) return { kind: "refused" };
    if (typeof line.event === "string") return { kind: "event", event: line };
    return { kind: "junk" };
}

// The next state after one event. Events about tabs that are not playing, and the mode events, change nothing.
function reduce(state, event) {
    const id = event.tab_id;
    if (event.event === "tab_audible") {
        const rest = without(state.audible, id);
        return {
            audible: event.audible === true ? rest.concat([tab_of(event)]) : rest,
            touched: mark(state.touched, id),
            pending: omit(state.pending, id)
        };
    }
    if (event.event === "tab_updated") {
        const text = { title: String(event.title || ""), url: String(event.url || "") };
        if (state.audible.some(t => t.tab_id === id)) {
            return {
                audible: state.audible.map(t => t.tab_id === id ? Object.assign({}, t, text) : t),
                touched: state.touched,
                pending: state.pending
            };
        }
        if (!(id in state.pending) && Object.keys(state.pending).length >= max_pending) return state;
        const pending = Object.assign({}, state.pending);
        pending[id] = text;
        return { audible: state.audible, touched: state.touched, pending: pending };
    }
    if (event.event === "tab_removed") {
        return { audible: without(state.audible, id), touched: mark(state.touched, id), pending: omit(state.pending, id) };
    }
    // Sharing went off: the host forgot every tab and no tab event follows until it is on again.
    if (event.event === "tabs_off") return empty;
    return state;
}

// Adds the audible tabs of a `tabs` reply that no event named yet, the least recently used first, so the tab the owner
// used last is the one that shows. The tabs already known stay newer than all of them. A title change that came before
// the reply is newer than the reply's text, so it wins. Whatever the reply, the held changes are dropped after.
function seed(state, reply) {
    const settled = { audible: state.audible, touched: state.touched, pending: {} };
    if (!reply || reply.ok !== true || !Array.isArray(reply.tabs)) return settled;
    const older = reply.tabs
        .filter(t => t && t.audible === true && typeof t.tab_id === "number" && !state.touched[t.tab_id])
        .sort((a, b) => (Number(a.last_accessed) || 0) - (Number(b.last_accessed) || 0))
        .map(t => Object.assign(tab_of(t), state.pending[t.tab_id] || {}));
    settled.audible = older.concat(state.audible);
    return settled;
}

function current(state) {
    return state.audible.length > 0 ? state.audible[state.audible.length - 1] : null;
}

// The chip text: the title, or the address when the page has none, cut to `max` characters.
function label_of(tab, max) {
    if (!tab) return "";
    const text = tab.title !== "" ? tab.title : tab.url;
    return text.length > max ? text.slice(0, max - 1) + "…" : text;
}

// The next wait before reconnecting, doubling to a cap; the bridge is often down for as long as Firefox is closed.
function next_backoff_ms(ms) {
    return Math.min(Math.max(ms, 1000) * 2, 30000);
}

function pause_request(tab_id) {
    return { verb: "run", command: "media play_pause", tab_id: tab_id };
}
