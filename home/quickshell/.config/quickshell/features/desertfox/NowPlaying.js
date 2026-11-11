.pragma library

// Which tabs are making sound, from the DesertFox bridge's event stream (wire format: host/README.md in DesertFox).
// Pure, so a node test can run it. A state is { audible: [tab...], touched: {tab_id: true} }, `audible` oldest first, so
// the last entry is the tab to show. `touched` is the tabs an event named since the stream started: a one-time tab list
// taken at connect is older than any of those and must not overwrite them.

var empty = { audible: [], touched: {} };

var refused_message = "too many subscribers";

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

function mark(touched, tab_id) {
    const next = Object.assign({}, touched);
    next[tab_id] = true;
    return next;
}

// One stream line as { kind: "ack" | "refused" | "event" | "junk", event? }. The first line of a stream is the ack or
// the refusal, which is how the host says its four subscribers are taken.
function parse_line(text) {
    let line;
    try {
        line = JSON.parse(text);
    } catch (e) {
        return { kind: "junk" };
    }
    if (!line || typeof line !== "object") return { kind: "junk" };
    if (line.ok === true) return { kind: "ack" };
    if (line.ok === false) return { kind: "refused", message: String(line.message || "") };
    if (typeof line.event === "string") return { kind: "event", event: line };
    return { kind: "junk" };
}

function is_refusal(parsed) {
    return parsed.kind === "refused" && parsed.message === refused_message;
}

// The next state after one event. Events about tabs that are not playing, and the mode events, change nothing.
function reduce(state, event) {
    const id = event.tab_id;
    if (event.event === "tab_audible") {
        const rest = without(state.audible, id);
        return {
            audible: event.audible === true ? rest.concat([tab_of(event)]) : rest,
            touched: mark(state.touched, id)
        };
    }
    if (event.event === "tab_updated") {
        if (!state.audible.some(t => t.tab_id === id)) return state;
        return {
            audible: state.audible.map(t => t.tab_id === id ? Object.assign({}, t, { title: String(event.title || ""), url: String(event.url || "") }) : t),
            touched: state.touched
        };
    }
    if (event.event === "tab_removed") {
        return { audible: without(state.audible, id), touched: mark(state.touched, id) };
    }
    // Sharing went off: the host forgot every tab and no tab event follows until it is on again.
    if (event.event === "tabs_off") return empty;
    return state;
}

// Adds the audible tabs of a `tabs` reply that no event named yet, the least recently used first, so the tab the owner
// used last is the one that shows. The tabs already known stay newer than all of them.
function seed(state, reply) {
    if (!reply || reply.ok !== true || !Array.isArray(reply.tabs)) return state;
    const older = reply.tabs
        .filter(t => t && t.audible === true && typeof t.tab_id === "number" && !state.touched[t.tab_id])
        .sort((a, b) => (Number(a.last_accessed) || 0) - (Number(b.last_accessed) || 0))
        .map(tab_of);
    return { audible: older.concat(state.audible), touched: state.touched };
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
