.pragma library

// The Projects picker's reading of the tmuxifier layouts (ProjectsProvider.qml), kept here so node can test it.

// Prints "L<TAB>stem<TAB>session_name" per layout, then "S<TAB>name" per running tmux session. The session_name read
// is voxcmd's layout_session_name (integrations/tmux.sh), so both match a layout to its session the same way.
var list_script = "dir=${TMUXIFIER_LAYOUT_PATH:-$HOME/.tmuxifier/layouts}; tab=$(printf '\\t');"
    + " for f in \"$dir\"/*.session.sh; do [ -f \"$f\" ] || continue;"
    + " printf 'L\\t%s\\t%s\\n' \"$(basename \"$f\" .session.sh)\" \"$(sed -nE 's/^[[:space:]]*session_name=\"([^\"]+)\".*/\\1/p' \"$f\" | head -n 1)\"; done;"
    + " tmux list-sessions -F \"S${tab}#{session_name}\" 2>/dev/null; true";

// tmux-layout's prettifying: dashes and underscores to spaces, each word capitalised.
function pretty_name(stem) {
    return stem.replace(/[-_]+/g, " ").split(/\s+/).filter(w => w !== "").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
}

function parse_listing(text) {
    const layouts = [];
    const sessions = [];
    for (const line of String(text || "").split("\n")) {
        const fields = line.split("\t");
        if (fields[0] === "L" && fields[1]) layouts.push({ stem: fields[1], session_name: fields[2] || "" });
        else if (fields[0] === "S" && fields.length > 1) sessions.push(fields.slice(1).join("\t"));
    }
    return { layouts: layouts, sessions: sessions };
}

// The session a layout creates is the session_name it sets, else its file name; tmux matches it exactly (`-t =name`).
function session_of(layout) {
    return layout.session_name || layout.stem;
}

function items_of(listing) {
    const running = new Set(listing.sessions);
    return listing.layouts.slice().sort((a, b) => a.stem < b.stem ? -1 : a.stem > b.stem ? 1 : 0).map(layout => {
        const session = session_of(layout);
        const is_running = running.has(session);
        return {
            id: layout.stem,
            label: pretty_name(layout.stem),
            description: is_running ? session + " · running" : session,
            keywords: [layout.stem, session],
            // A blank glyph keeps the icon column empty, so the running dots line up without an icon beside them.
            glyph: is_running ? "\u25cf" : " ",
            stem: layout.stem,
            session: session,
            running: is_running
        };
    });
}
