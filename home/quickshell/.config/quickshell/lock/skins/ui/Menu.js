// home/quickshell/.config/quickshell/lock/skins/ui/Menu.js
.pragma library

// Menu state for the skins with game menus, kept in ctx.scene as "<prefix>:<item>:<note>"; skins keep their own keys and cues.

const login_options = ["session", "safe", "text", "firmware", "back"];
const lock_options = ["firmware", "back"];

function opt_items(login) {
    return login ? login_options.slice() : lock_options.slice();
}

function item_of(scene, prefix, fallback) {
    return scene.startsWith(prefix) ? scene.split(":")[1] : fallback;
}

function note_of(scene, prefix) {
    return scene.startsWith(prefix) ? (scene.split(":")[2] || "") : "";
}

// The scene without its note when it is under one of `prefixes` and has one, else "".
function note_cleared(scene, prefixes) {
    for (const prefix of prefixes) {
        if (scene.startsWith(prefix)) return note_of(scene, prefix) !== "" ? prefix + item_of(scene, prefix, "") : "";
    }
    return "";
}

// labels maps each option to its text; "session" is followed by the ctx's session name, and anything unknown reads as back.
function opt_label(ctx, item, labels) {
    switch (item) {
    case "session": return labels.session + (ctx && "session_name" in ctx ? ctx.session_name : "");
    case "safe": return labels.safe;
    case "text": return labels.text;
    case "firmware": return labels.firmware;
    default: return labels.back;
    }
}

function wrap(at, count, forward) {
    return (at + (forward ? 1 : count - 1)) % count;
}

function cycle(items, item, forward) {
    return items[wrap(items.indexOf(item), items.length, forward)];
}

function blocked(ctx) {
    return !ctx || !("scene" in ctx) || ctx.buffer_length > 0 || ctx.checking || ctx.granted;
}

// Control without Alt, so AltGr letters still count as text.
function ctrl(event) {
    return !!(event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier);
}

function enter(event, ctrl_held) {
    return !ctrl_held && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter);
}

function printable(event, ctrl_held) {
    return !ctrl_held && event.text !== "" && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127;
}

// Reboot and power off: the first press arms `prefix + item`, the second runs it on a power_live ctx and only notes it on a preview.
function power_step(ctx, prefix, item, note) {
    if (note === "armed") {
        ctx.scene = prefix + item + (ctx.power_live ? ":running" : ":preview");
        if (ctx.power_live) ctx.power_request(item);
    } else {
        ctx.scene = prefix + item + ":armed";
    }
}

// Enter on an Options item; firmware and text login need a second press like power_step.
function opt_step(ctx, item, note, back_scene, safe_scene) {
    if (item === "back") {
        ctx.scene = back_scene;
    } else if (item === "session") {
        if ("session_request" in ctx) ctx.session_request();
    } else if (item === "safe") {
        if ("safe_request" in ctx) ctx.safe_request();
        ctx.scene = safe_scene;
    } else if (note === "armed") {
        ctx.scene = "opt:" + item + (ctx.power_live ? ":running" : ":preview");
        if (ctx.power_live) {
            if (item === "firmware") ctx.power_request("firmware");
            else if (item === "text" && "fallback_request" in ctx) ctx.fallback_request();
        }
    } else {
        ctx.scene = "opt:" + item + ":armed";
    }
}
