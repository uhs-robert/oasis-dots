// home/quickshell/.config/quickshell/components/Search.js
.pragma library

function starts_word(text, i) {
    return i === 0 || !/[a-z0-9]/i.test(text.charAt(i - 1));
}

// Where query sits in text, case-insensitively, preferring a word start; -1 when absent.
function locate(text, query) {
    if (!query) return -1;
    const hay = String(text || "").toLowerCase();
    const needle = query.toLowerCase();
    let first = -1;
    for (let i = hay.indexOf(needle); i >= 0; i = hay.indexOf(needle, i + 1)) {
        if (starts_word(hay, i)) return i;
        if (first < 0) first = i;
    }
    return first;
}

function matches(rows, query) {
    const found = [];
    if (!query || !rows) return found;
    for (let i = 0; i < rows.length; i++) if (locate(rows[i], query) >= 0) found.push(i);
    return found;
}

// The first row matching at a word start, else the first row matching at all.
function best(rows, query) {
    let first = -1;
    for (const i of matches(rows, query)) {
        const text = String(rows[i]);
        if (starts_word(text, locate(text, query))) return i;
        if (first < 0) first = i;
    }
    return first;
}

function escape(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// StyledText for a row label with the query underlined in color; null when it does not match.
function mark(label, query, color) {
    const text = String(label || "");
    const i = locate(text, query);
    if (i < 0) return null;
    const end = i + query.length;
    return escape(text.slice(0, i)) + "<u><font color=\"" + color + "\">" + escape(text.slice(i, end)) + "</font></u>" + escape(text.slice(end));
}
