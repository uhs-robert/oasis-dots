.pragma library

// The hover-open state machine behind HoverPopup, pure so a test can drive it without timers or a compositor.
//
// A mode is "idle", "pending" (open timer running), "hover_open" (opened by hover; closes when the pointer leaves both
// the module and the popup) or "pinned" (opened by a click or from outside; only a click, an outside click or another
// popup ends it) or "suppressed" (the popup was just closed with the pointer still on the module; hover does not
// reopen it until the pointer has left and come back) or "settling" (a pinned popup was closed with no pointer on
// the module: a click on the bar can land on the popup layer, and the module sees the pointer again a moment later,
// which then reads as "suppressed" instead of a new hover) or "swapping" (another module's hover-opened popup is open
// and the short swap delay is running on the open timer). Every function returns { mode, open_timer, close_timer, action }:
// the timers are "start", "stop" or "keep", the action is "none", "open", "swap" (a hover open that takes over the open
// popup in place) or "close".

function result(mode, open_timer, close_timer, action) {
    return { mode: mode, open_timer: open_timer, close_timer: close_timer, action: action };
}

// Whether entering this module may take over the open popup: only from idle, and only while the open popup is another
// module's hover-opened one (`other_hover_open`), so a pinned, key or IPC popup is never replaced.
function swap_ok(mode, inside, other_hover_open) {
    return mode === "idle" && inside && other_hover_open;
}

// The pointer entered or left the module or the popup. `nothing_open`: no popup of any kind is open, since hover never
// replaces one the owner pinned; `other_hover_open`: see swap_ok.
function inside_changed(mode, inside, nothing_open, other_hover_open) {
    if (mode === "suppressed") return result(inside ? mode : "idle", "keep", "stop", "none");
    if (mode === "settling") return inside ? result("suppressed", "keep", "stop", "none") : result(mode, "keep", "keep", "none");
    if (inside) {
        if (mode === "idle" && nothing_open) return result("pending", "start", "stop", "none");
        if (swap_ok(mode, inside, !!other_hover_open)) return result("swapping", "start", "stop", "none");
        return result(mode, "keep", "stop", "none");
    }
    if (mode === "pending" || mode === "swapping") return result("idle", "stop", "stop", "none");
    if (mode === "hover_open") return result(mode, "stop", "start", "none");
    return result(mode, "stop", "keep", "none");
}

// The last open popup closed while the pointer is still on this module (it came straight from another module): start
// the open delay now, since no `inside` change will follow.
// A swap still waiting falls back to the full open delay, since there is nothing left to swap from.
function nothing_open_now(mode, inside) {
    if ((mode === "idle" || mode === "swapping") && inside) return result("pending", "start", "stop", "none");
    return result(mode, "keep", "keep", "none");
}

// The open delay ran out: the pointer must still be there and nothing else open. The swap delay ran out: the pointer
// must still be there and the popup to take over still another module's hover-opened one.
function open_elapsed(mode, inside, nothing_open, other_hover_open) {
    if (mode === "swapping") return inside && other_hover_open ? result("hover_open", "stop", "stop", "swap") : result("idle", "stop", "stop", "none");
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
    if (mode !== "hover_open" && mode !== "pinned") return result("pinned", "stop", "stop", "none");
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

// What Popups.open(name, ..., swap) records as swap_from: the open popup it replaces, or null for a plain open when
// nothing is open, the popup is the same one, or it is on another screen (a layer cannot move monitors; each screen's
// bar has one edge, so the same screen is also the same edge).
function swap_source(swap, open_name, open_screen, name, screen_name) {
    if (!swap || open_name === "" || open_name === name || open_screen !== screen_name) return null;
    return { name: open_name, to: name, screen_name: open_screen, extent: 0 };
}

// Whether a mode change pins a hover-opened popup that is still open: its window has no keyboard yet (a hover open takes
// none), so Escape would go nowhere until the owner clicked inside it. The caller asks the popup for the keyboard.
function pin_grabs_keyboard(from_mode, to_mode, open_here) {
    return from_mode === "hover_open" && to_mode === "pinned" && open_here;
}
