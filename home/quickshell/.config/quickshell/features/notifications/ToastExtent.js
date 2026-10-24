.pragma library

// Pure helpers for the toast drawer's single animated depth (NotificationToasts.qml), kept here so node can test them.

// What a tall card is allowed to measure when the drawer's window is sized; a taller one is clipped, not grown into.
const TALL_CARD = 200;
const SPACING = 8;
// The toasts' own inset from the drawer body's edges.
const PAD = 8;
const MAX_CARDS = 5;

// The fixed window depth: five tall cards, or what the screen leaves, whichever is less. A fuller stack clips its last
// card instead of dropping the oldest.
function window_depth(available) {
    return Math.max(0, Math.min(MAX_CARDS * TALL_CARD + (MAX_CARDS - 1) * SPACING + PAD * 2, available));
}

// The depth the drawer opens to: the cards' height, capped at `cap`. An empty stack keeps `last`, so the fold has a
// height to shrink from.
function stack_height(content_height, count, last, cap) {
    if (count === 0) return last;
    return Math.max(0, Math.min(content_height, cap));
}

// A growing drawer eases out, a shrinking one in and faster.
function opening(target, extent) {
    return target > extent;
}

// Whether a card's hover changes its timer. Cards slide under a still cursor while the drawer moves, so hover is
// ignored then and settled once: pause a hovered card not yet held, resume a held one the cursor has left.
function hover_action(moving, hovered, held) {
    if (moving || hovered === held) return "none";
    return hovered ? "pause" : "resume";
}
