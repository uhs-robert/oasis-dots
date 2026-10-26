.pragma library

// Text rules for the media well, pure so a node test covers them.

// Cuts to `max_chars` characters, the last being an ellipsis when anything was cut.
function clip(text, max_chars) {
    if (text.length <= max_chars) return text;
    return text.slice(0, Math.max(0, max_chars - 1)).replace(/\s+$/, "") + "…";
}

// The lines the well shows, from the shown fields: "inline" joins them as "Artist - Title" on one line, "stacked"
// puts the title over a smaller artist line. Empty fields and hidden fields leave no line.
function lines(title, artist, show_title, show_artist, layout) {
    const t = show_title && title ? title : "";
    const a = show_artist && artist ? artist : "";
    if (layout === "stacked") {
        const out = [];
        if (t) out.push({ text: t, small: false });
        if (a) out.push({ text: a, small: !!t });
        return out;
    }
    const joined = [a, t].filter(s => s !== "").join(" - ");
    return joined ? [{ text: joined, small: false }] : [];
}

function format_time(seconds) {
    const s = Math.max(0, Math.floor(seconds || 0));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const r = s % 60;
    const pad = n => (n < 10 ? "0" + n : "" + n);
    return h > 0 ? h + ":" + pad(m) + ":" + pad(r) : m + ":" + pad(r);
}

function ratio(position, length) {
    if (!(length > 0)) return 0;
    return Math.max(0, Math.min(1, position / length));
}

// Whether the marquee should run: wanted, visible and the text really overflows its window.
function marquee_running(wanted, visible, overflow) {
    return !!wanted && !!visible && overflow > 0;
}
