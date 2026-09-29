// home/quickshell/.config/quickshell/lock/skins/mgs2/Art.js
.pragma library

// The menu face: unicase, wide and square like the game's menu type, on a 7 wide, 5 tall grid.
const glyphs = {
    A: [[[0, 5], [0, 1.3], [1.3, 0], [7, 0], [7, 5]], [[0, 2.6], [7, 2.6]]],
    B: [[[0, 0], [0, 5], [7, 5], [7, 2.5], [0, 2.5]], [[0, 0], [6, 0], [6, 2.5]]],
    C: [[[7, 0], [0, 0], [0, 5], [7, 5]]],
    D: [[[0, 0], [5.7, 0], [7, 1.3], [7, 5], [0, 5], [0, 0]]],
    E: [[[7, 0], [0, 0], [0, 5], [7, 5]], [[0, 2.5], [6, 2.5]]],
    F: [[[7, 0], [0, 0], [0, 5]], [[0, 2.5], [6, 2.5]]],
    G: [[[7, 0], [0, 0], [0, 5], [7, 5], [7, 2.6], [4, 2.6]]],
    H: [[[0, 0], [0, 5]], [[7, 0], [7, 5]], [[0, 2.5], [7, 2.5]]],
    I: [[[0, 0], [0, 5]]],
    J: [[[7, 0], [7, 5], [0, 5], [0, 3.4]]],
    K: [[[0, 0], [0, 5]], [[6.5, 0], [0.5, 2.6], [7, 5]]],
    L: [[[0, 0], [0, 5], [7, 5]]],
    M: [[[0, 5], [0, 0], [7, 0], [7, 5]], [[3.5, 0], [3.5, 5]]],
    N: [[[0, 5], [0, 0], [7, 0], [7, 5]]],
    O: [[[0, 0], [7, 0], [7, 5], [0, 5], [0, 0]]],
    P: [[[0, 5], [0, 0], [7, 0], [7, 2.6], [0, 2.6]]],
    Q: [[[0, 0], [7, 0], [7, 5], [0, 5], [0, 0]], [[4.6, 3.4], [7.4, 5.6]]],
    R: [[[0, 5], [0, 0], [7, 0], [7, 2.6], [0, 2.6]], [[3.4, 2.6], [7, 5]]],
    S: [[[7, 0], [0, 0], [0, 2.5], [7, 2.5], [7, 5], [0, 5]]],
    T: [[[0, 0], [7, 0]], [[3.5, 0], [3.5, 5]]],
    U: [[[0, 0], [0, 5], [7, 5], [7, 0]]],
    V: [[[0, 0], [3.5, 5], [7, 0]]],
    W: [[[0, 0], [0, 5], [7, 5], [7, 0]], [[3.5, 2.2], [3.5, 5]]],
    X: [[[0, 0], [7, 5]], [[7, 0], [0, 5]]],
    Y: [[[0, 0], [0, 2.5], [7, 2.5]], [[7, 0], [7, 5], [0, 5]]],
    Z: [[[0, 0], [7, 0], [0, 5], [7, 5]]],
    "0": [[[0, 0], [7, 0], [7, 5], [0, 5], [0, 0]], [[2.4, 3.6], [4.6, 1.4]]],
    "1": [[[1.4, 0.9], [3, 0], [3, 5]]],
    "2": [[[0, 0], [7, 0], [7, 2.5], [0, 2.5], [0, 5], [7, 5]]],
    "3": [[[0, 0], [7, 0], [7, 5], [0, 5]], [[2, 2.5], [7, 2.5]]],
    "4": [[[0, 0], [0, 2.9], [7, 2.9]], [[5.2, 0], [5.2, 5]]],
    "5": [[[7, 0], [0, 0], [0, 2.5], [7, 2.5], [7, 5], [0, 5]]],
    "6": [[[7, 0], [0, 0], [0, 5], [7, 5], [7, 2.5], [0, 2.5]]],
    "7": [[[0, 0], [7, 0], [7, 5]]],
    "8": [[[0, 0], [7, 0], [7, 5], [0, 5], [0, 0]], [[0, 2.5], [7, 2.5]]],
    "9": [[[7, 2.5], [0, 2.5], [0, 0], [7, 0], [7, 5], [0, 5]]],
    "/": [[[0, 5], [5, 0]]],
    "-": [[[0, 2.5], [5, 2.5]]],
    "_": [[[0, 5], [7, 5]]],
    "?": [[[0, 0], [7, 0], [7, 2.5], [3.5, 2.5], [3.5, 3.4]]]
};
const widths = { I: 0, "1": 3, "/": 5, "-": 5, " ": 3.5, ":": 1, ".": 1, "#": 3.6 };
const dots = { ":": [[0, 1], [0, 3.6]], ".": [[0, 3.6]], "?": [[3.1, 4.2]] };

// `text` in the menu face as {d: stroke path, fill: dot path, vw, vh}, in glyph units with the stroke's padding.
function seg(text, gap, sw) {
    const pad = sw;
    let x = 0, d = "", fill = "";
    const box = (bx, by, w, h) => "M" + (bx + pad) + " " + (by + pad) + "h" + w + "v" + h + "h" + (-w) + "Z";
    for (const ch of String(text).toUpperCase()) {
        const w = ch in widths ? widths[ch] : 7;
        for (const line of glyphs[ch] || []) d += "M" + line.map(p => (x + p[0] + pad).toFixed(2) + " " + (p[1] + pad).toFixed(2)).join("L");
        for (const p of dots[ch] || []) fill += box(x + p[0] - sw / 2, p[1] - sw / 2 + 0.4, sw * 1.4, sw * 1.4);
        if (ch === "#") fill += box(x, 1, 3.6, 3.4);
        x += w + gap;
    }
    x = Math.max(x - gap, 0.1);
    return { d: d || "M0 0", fill: fill || "M0 0", vw: x + pad * 2, vh: 5 + pad * 2 };
}

// Seeded random, so the art is the same on every load.
function rng(seed) {
    let s = seed | 0;
    return () => {
        s = (s + 0x6D2B79F5) | 0;
        let t = Math.imul(s ^ (s >>> 15), 1 | s);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

function hex(cx, cy, r) {
    const out = [];
    for (let i = 0; i < 6; i++) {
        const a = Math.PI / 6 + i * Math.PI / 3;
        out.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
    }
    return out;
}

function ring(points) {
    return "M" + points.map(v => v[0].toFixed(1) + " " + v[1].toFixed(1)).join("L") + "Z";
}

function circle(cx, cy, r) {
    return "M" + (cx + r).toFixed(1) + " " + cy.toFixed(1) + "A" + r + " " + r + " 0 1 0 " + (cx - r).toFixed(1) + " " + cy.toFixed(1) + "A" + r + " " + r + " 0 1 0 " + (cx + r).toFixed(1) + " " + cy.toFixed(1);
}

// The red molecule line art: a chain of rings with bonds, end circles and atom labels, as {d, labels: [{x, y, t}]}.
function molecule(seed, x, y, s) {
    const r = rng(seed), R = 34 * s;
    let d = "", cx = x, cy = y;
    const labels = [];
    const rings = 2 + Math.floor(r() * 3);
    for (let i = 0; i < rings; i++) {
        const h = hex(cx, cy, R);
        d += ring(h);
        const k = Math.floor(r() * 6), v = h[k];
        const a = Math.PI / 6 + k * Math.PI / 3;
        const len = R * (0.9 + r() * 1.4);
        const ex = v[0] + Math.cos(a) * len, ey = v[1] + Math.sin(a) * len;
        d += "M" + v[0].toFixed(1) + " " + v[1].toFixed(1) + "L" + ex.toFixed(1) + " " + ey.toFixed(1);
        if (r() < 0.6) {
            const bx = ex + (r() < 0.5 ? -1 : 1) * R * 0.9, by = ey + R * 0.5;
            d += "L" + bx.toFixed(1) + " " + by.toFixed(1);
            if (r() < 0.6) d += circle(bx, by + 8 * s, 7 * s);
            if (r() < 0.5) labels.push({ x: bx + 6, y: by - 4, t: ["OH", "N", "O", "CH3", "NH"][Math.floor(r() * 5)] });
        }
        const dir = [0, Math.PI / 3, -Math.PI / 3][Math.floor(r() * 3)];
        cx += Math.cos(dir) * R * Math.sqrt(3);
        cy += Math.sin(dir) * R * Math.sqrt(3);
    }
    return { d: d, labels: labels };
}

// The grey structure diagram behind NAME ENTRY.
function diagram() {
    const c = [330, 560], R = 140;
    let d = "";
    const outer = hex(c[0], c[1], R);
    d += ring(outer);
    for (const v of outer) d += ring(hex(v[0], v[1], 26));
    for (const v of hex(c[0], c[1] + 90, 60)) d += ring(hex(v[0], v[1], 20));
    d += ring(hex(c[0], c[1] + 90, 26));
    const labels = [["e=mc2", 470, 360], ["oasis-(c)", 450, 450], ["n+(c)", 200, 450], ["arch-(x)x86", 110, 600], ["w24c", 330, 680], ["x", 390, 400]];
    return { d: d, labels: labels.map(l => ({ t: l[0], x: l[1], y: l[2] })) };
}
