.pragma library

// The keys a mode offers, in groups by purpose. Each key is [cap, label]; the hint bar shows every one of them.
function groups(mode, carrying, vertical, can_forget) {
    const quit = ["q", "quit"];
    const help = ["?", "help"];
    if (mode === "monitor") {
        return [
            { name: "pick", keys: [["hjkl", "monitor"], ["Enter", "edit bar"]] },
            { name: "leave", keys: [["Esc", "close"], help] }
        ];
    }
    if (mode === "hidden" && carrying) {
        return [
            { name: "place", keys: [["h/l", "place"], ["Enter", "drop"]] },
            { name: "leave", keys: [["Esc", "cancel"], quit, help] }
        ];
    }
    if (mode === "hidden") {
        return [
            { name: "pick", keys: [["h/l", "select"], ["Enter", "pick up"]] },
            { name: "leave", keys: [["Tab", "back"], quit, help] }
        ];
    }
    if (mode === "visual") {
        const edit = [["h j k l", "move to edge"]];
        if (can_forget) edit.push(["x", "forget"]);
        return [
            { name: "move", keys: edit },
            { name: "history", keys: [["u", "undo"], ["^R", "redo"]] },
            { name: "leave", keys: [["Enter", "done"], quit, help] }
        ];
    }
    return [
        { name: "select", keys: [[vertical ? "h/l j/k" : "h/l", "select"]] },
        { name: "edit", keys: [[vertical ? "H/L J/K" : "H/L", "move"], ["x", "hide"], ["c", "compact"], ["o", "own"]] },
        { name: "modes", keys: [["Tab", "hidden"], ["V", "bar"]] },
        { name: "history", keys: [["u", "undo"], ["^R", "redo"]] },
        { name: "leave", keys: [["Esc", "back"], quit, help] }
    ];
}
