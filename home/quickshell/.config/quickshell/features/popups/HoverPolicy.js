.pragma library

// The hover-open state machine behind HoverPopup, pure so a test can drive it without timers or a compositor.
//
// A mode is "idle", "pending" (open timer running), "hover_open" (opened by hover; closes when the pointer leaves both
// the module and the popup) or "pinned" (opened by a click or from outside; only a click, an outside click or another
// popup ends it) or "suppressed" (the popup was just closed with the pointer still on the module; hover does not
// reopen it until the pointer has left and come back) or "settling" (a pinned popup was closed with no pointer on
// the module: a click on the bar can land on the popup layer, and the module sees the pointer again a moment later,
// which then reads as "suppressed" instead of a new hover). Every function returns { mode, open_timer, close_timer, action }: the timers are "start", "stop" or
// "keep", the action is "none", "open" or "close".

function result(mode, open_timer, close_timer, action) {
    return { mode: mode, open_timer: open_timer, close_timer: close_timer, action: action };
}

// The pointer entered or left the module or the popup. `nothing_open`: no popup of any kind is open, since hover never
// replaces one the owner pinned.
function inside_changed(mode, inside, nothing_open) {
    if (mode === "suppressed") return result(inside ? mode : "idle", "keep", "stop", "none");
    if (mode === "settling") return inside ? result("suppressed", "keep", "stop", "none") : result(mode, "keep", "keep", "none");
    if (inside) {
        if (mode === "idle" && nothing_open) return result("pending", "start", "stop", "none");
        return result(mode, "keep", "stop", "none");
    }
    if (mode === "pending") return result("idle", "stop", "stop", "none");
    if (mode === "hover_open") return result(mode, "stop", "start", "none");
    return result(mode, "stop", "keep", "none");
}

// The open delay ran out: the pointer must still be there and nothing else open.
function open_elapsed(mode, inside, nothing_open) {
    if (mode !== "pending") return result(mode, "keep", "keep", "none");
    if (inside && nothing_open) return result("hover_open", "stop", "stop", "open");
    return result("idle", "stop", "stop", "none");
}

// The grace after leaving ran out: close unless the pointer came back (which already stopped this timer; the check
// covers a timer that fired in the same turn as the re-entry).
function close_elapsed(mode, inside) {
    if (mode === "settling") return result("idle", "keep", "stop", "none");
    if (mode !== "hover_open") return result(mode, "keep", "keep", "none");
    if (inside) return result(mode, "keep", "stop", "none");
    return result("idle", "stop", "stop", "close");
}

// A click on the module: pins an open or pending popup, opens a closed one pinned, and closes a pinned one (suppressed, since the pointer is still on the module).
function clicked(mode, open_here) {
    if (mode === "pinned" && open_here) return result("suppressed", "stop", "stop", "close");
    if (open_here) return result("pinned", "stop", "stop", "none");
    return result("pinned", "stop", "stop", "open");
}

// Popups.open_name changed (or was read at start): `open_here` is whether it now names this popup, `inside` whether the
// pointer is on the module or the popup. A pinned popup closed under the pointer (a click on the module, say) must not
// pop straight back up from the hover that is still there.
function popup_changed(mode, open_here, inside) {
    if (!open_here) {
        if (mode === "pinned") return inside ? result("suppressed", "stop", "stop", "none") : result("settling", "stop", "start", "none");
        return result(mode === "suppressed" && inside ? mode : mode === "settling" ? mode : "idle", "stop", mode === "settling" ? "keep" : "stop", "none");
    }
    if (mode === "idle" || mode === "pending" || mode === "suppressed" || mode === "settling") return result("pinned", "stop", "stop", "none");
    return result(mode, "keep", "keep", "none");
}

// The module went away (hidden, disabled, destroyed): a hover-opened popup closes with it, a pinned one stays.
function disabled(mode, open_here) {
    return result(mode === "pinned" ? "pinned" : "idle", "stop", "stop", mode === "hover_open" && open_here ? "close" : "none");
}

// A press inside the popup pins a hover-opened one, like a click on the module.
function popup_pressed(mode) {
    return mode === "hover_open" ? result("pinned", "stop", "stop", "none") : result(mode, "keep", "keep", "none");
}

// Whether the open popup is this module's own: the same name and, when the module knows its screen, the same screen,
// so another monitor's hover-opened popup does not read as an outside open here.
function open_here(open_name, open_screen, popup_name, screen_name) {
    return open_name === popup_name && (!screen_name || open_screen === screen_name);
}
