.pragma library

// Vim word classes: blank, keyword characters, other punctuation.
function char_class(c) {
    return /\s/.test(c) ? 0 : /\w/.test(c) ? 1 : 2;
}

function word_forward(t, p) {
    const n = t.length;
    const c = p < n ? char_class(t[p]) : 0;
    if (c !== 0) while (p < n && char_class(t[p]) === c) p++;
    while (p < n && char_class(t[p]) === 0) p++;
    return p;
}

function word_end(t, p) {
    const n = t.length;
    p++;
    while (p < n && char_class(t[p]) === 0) p++;
    if (p >= n) return Math.max(0, n - 1);
    const c = char_class(t[p]);
    while (p + 1 < n && char_class(t[p + 1]) === c) p++;
    return p;
}

function word_back(t, p) {
    if (p <= 0) return 0;
    p--;
    while (p > 0 && char_class(t[p]) === 0) p--;
    const c = char_class(t[p]);
    while (p > 0 && char_class(t[p - 1]) === c) p--;
    return p;
}

// Where a motion lands from p, and whether an operator over it includes the landing character.
function motion(ch, t, p) {
    const n = t.length;
    if (ch === "h") return { to: Math.max(0, p - 1), incl: false };
    if (ch === "l") return { to: Math.min(n, p + 1), incl: false };
    if (ch === "w") return { to: word_forward(t, p), incl: false };
    if (ch === "b") return { to: word_back(t, p), incl: false };
    if (ch === "e") return { to: word_end(t, p), incl: true };
    if (ch === "0") return { to: 0, incl: false };
    if (ch === "^") return { to: Math.max(0, t.search(/\S/)), incl: false };
    if (ch === "$") return { to: Math.max(0, n - 1), incl: true };
    return null;
}
