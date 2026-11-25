.pragma library

// The keys a mode offers, in groups by purpose. Each key is [cap, label]; the hint bar shows every one of them.
// `compact` is what `c` acts on now: the selected module's override in NORMAL ("inherit", "on", "off", "none" with no
// compact form), the whole bar's compact in VISUAL ("on", "off"). `other_bar` is the edge of the screen's other bar
// ("top", "bottom"), "" with one bar: `j` or `k` toward it edits it, Shift moves the module there.
function groups(mode, carrying, vertical, can_forget, compact, other_bar) {
    const compact_key = ["c", "compact: " + (compact || "off")];
    const quit = ["q", "quit"];
    const help = ["?", "help"];
    const hide = ["i", "hide"];
    if (mode === "monitor") {
        return [
            { name: "pick", keys: [["hjkl", "monitor"], ["Enter", "edit bar"]] },
            { name: "leave", keys: [["Esc", "close"], quit, hide, help] }
        ];
    }
    if (mode === "hidden" && carrying) {
        return [
            { name: "place", keys: [["h/l", "place"], ["Enter", "drop"]] },
            { name: "leave", keys: [["Esc", "cancel"], quit, hide, help] }
        ];
    }
    if (mode === "hidden") {
        return [
            { name: "pick", keys: [["h/l", "select"], ["Enter", "pick up"]] },
            { name: "leave", keys: [["Esc/Tab", "back"], quit, hide, help] }
        ];
    }
    if (mode === "visual") {
        const edit = [["h j k l", "move to edge"], compact_key];
        if (can_forget) edit.push(["x", "forget"]);
        return [
            { name: "move", keys: edit },
            { name: "history", keys: [["u", "undo"], ["^R", "redo"]] },
            { name: "leave", keys: [["Enter/Esc", "done"], quit, hide, help] }
        ];
    }
    const toward = other_bar === "bottom" ? "j" : "k";
    const select = [[vertical ? "h/l j/k" : "h/l", "select"]];
    const edit = [[vertical ? "H/L J/K" : "H/L", "move"]];
    if (other_bar) {
        select.push([toward, other_bar + " bar"]);
        edit.push([toward.toUpperCase(), "to " + other_bar + " bar"]);
    }
    return [
        { name: "select", keys: select },
        { name: "edit", keys: edit.concat([["x", "hide"], compact_key, ["o", "own"]]) },
        { name: "modes", keys: [["Tab", "hidden"], ["V", "bar"]] },
        { name: "history", keys: [["u", "undo"], ["^R", "redo"]] },
        { name: "leave", keys: [["Esc", "back"], quit, hide, help] }
    ];
}

// The key specs `BarEditor.press` takes that a mode's groups list: "h/l" and "h j k l" name several, "^R" is Ctrl+r.
function keys_of(groups) {
    const out = [];
    for (const group of groups) {
        for (const cap of group.keys.map(k => k[0])) {
            for (const part of cap.split("/")) {
                if (part === "^R") out.push("Ctrl+r");
                else if (/^[A-Z][a-z]+$/.test(part)) out.push(part);
                else part.replace(/ /g, "").split("").forEach(c => out.push(c));
            }
        }
    }
    return out;
}
