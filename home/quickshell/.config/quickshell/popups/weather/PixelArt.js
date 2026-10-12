// home/quickshell/.config/quickshell/popups/weather/PixelArt.js
.pragma library

// Weather drawn as four-shade pixel grids: rows of "0"-"3" (darkest to lightest) and "." for clear.

function kind(code, is_day) {
    if (code >= 95) return "storm";
    if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "snow";
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return "rain";
    if (code >= 51 && code <= 57) return "drizzle";
    if (code === 45 || code === 48) return "fog";
    if (code === 3) return "cloud";
    if (code === 1 || code === 2) return is_day ? "partly" : "partly_night";
    return is_day ? "clear" : "night";
}

function sq(v) {
    return v * v;
}

function grid(w, h, bg) {
    const g = [];
    for (let y = 0; y < h; y++) {
        const row = [];
        for (let x = 0; x < w; x++) row.push(bg ? bg(x, y) : ".");
        g.push(row);
    }
    return g;
}

function put(g, x, y, c) {
    if (y >= 0 && y < g.length && x >= 0 && x < g[y].length) g[y][x] = c;
}

// A union of circles cut flat at `base`: dark rim, light body, a mid-shade underside.
function cloud(g, circles, base) {
    const inside = (x, y) => y + 0.5 <= base && circles.some(c => sq(x + 0.5 - c[0]) + sq(y + 0.5 - c[1]) <= c[2] * c[2]);
    const out = [];
    for (let y = 0; y < g.length; y++) {
        for (let x = 0; x < g[y].length; x++) {
            if (!inside(x, y)) continue;
            const rim = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1);
            out.push([x, y, rim ? "0" : y >= base - 2 ? "2" : "3"]);
        }
    }
    out.forEach(p => put(g, p[0], p[1], p[2]));
}

const SUN = [
    ".....3.....",
    ".3.......3.",
    "....000....",
    "...03330...",
    "..0333330..",
    "3.0333330.3",
    "..0333330..",
    "...03330...",
    "....000....",
    ".3.......3.",
    ".....3....."
];

const SUN_SMALL = [
    "...3...",
    "..000..",
    ".03330.",
    "3033303",
    ".03330.",
    "..000..",
    "...3..."
];

function stamp(g, x, y, art) {
    art.forEach((row, dy) => {
        for (let dx = 0; dx < row.length; dx++) if (row[dx] !== ".") put(g, x + dx, y + dy, row[dx]);
    });
}

// A crescent with a dark rim and light body.
function moon(g, cx, cy, r) {
    const inside = (x, y) => sq(x + 0.5 - cx) + sq(y + 0.5 - cy) <= r * r && sq(x + 0.5 - cx - r * 0.6) + sq(y + 0.5 - cy + r * 0.35) > r * r * 0.64;
    const out = [];
    for (let y = 0; y < g.length; y++) {
        for (let x = 0; x < g[y].length; x++) {
            if (!inside(x, y)) continue;
            const rim = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1);
            out.push([x, y, rim ? "0" : "3"]);
        }
    }
    out.forEach(p => put(g, p[0], p[1], p[2]));
}

function drops(g, list, length) {
    list.forEach(p => {
        for (let i = 0; i < length; i++) put(g, p[0], p[1] + i, "3");
    });
}

function flakes(g, list) {
    list.forEach(p => {
        put(g, p[0], p[1], "3");
        put(g, p[0] - 1, p[1], "2");
        put(g, p[0] + 1, p[1], "2");
        put(g, p[0], p[1] - 1, "2");
        put(g, p[0], p[1] + 1, "2");
    });
}

function bolt(g, x, y) {
    [[2, 0], [1, 1], [2, 1], [0, 2], [1, 2], [2, 2], [3, 2], [2, 3], [1, 4], [0, 5]].forEach(p => put(g, x + p[0], y + p[1], "3"));
}

function fog(g, y0, count, gap) {
    for (let i = 0; i < count; i++) {
        const y = y0 + i * gap;
        for (let x = 0; x < g[0].length; x++) {
            if ((x + i * 3) % 7 < 5) put(g, x, y, i % 2 ? "2" : "3");
        }
    }
}

// The condition over grid g, its cloud cluster starting at column ox.
function paint(g, k, ox, oy) {
    const clouds = [[ox + 4, oy + 5.5, 3.3], [ox + 8, oy + 3.5, 4.2], [ox + 11.6, oy + 6, 2.8]];
    const base = oy + 8.5;
    if (k === "clear") stamp(g, ox + 3, oy, SUN);
    else if (k === "night") moon(g, ox + 8, oy + 5.5, 5);
    else if (k === "partly" || k === "partly_night") {
        if (k === "partly") stamp(g, ox + 8, oy, SUN_SMALL);
        else moon(g, ox + 12, oy + 3.5, 3.4);
        cloud(g, [[ox + 4, oy + 7, 2.8], [ox + 7.5, oy + 5.5, 3.4], [ox + 10.5, oy + 7.5, 2.4]], oy + 9.5);
    } else if (k === "fog") {
        fog(g, oy + 2, 4, 2);
    } else {
        cloud(g, clouds, base);
        if (k === "drizzle") drops(g, [[ox + 4, oy + 10], [ox + 8, oy + 11], [ox + 12, oy + 10]], 1);
        else if (k === "rain") drops(g, [[ox + 3, oy + 10], [ox + 6, oy + 11], [ox + 9, oy + 10], [ox + 12, oy + 11]], 2);
        else if (k === "snow") flakes(g, [[ox + 4, oy + 11], [ox + 9, oy + 12], [ox + 13, oy + 10]]);
        else if (k === "storm") bolt(g, ox + 7, oy + 8);
    }
}

function rows(g) {
    return g.map(r => r.join(""));
}

// The Pokédex sprite: 16x13, clear background.
function sprite(code, is_day) {
    const g = grid(16, 13, null);
    paint(g, kind(code, is_day), 0, 0);
    return rows(g);
}

// A Game Boy Camera photo, 24x18: dithered sky over a dark horizon and speckled ground.
function photo(code, index) {
    const sky = (x, y) => y < 6 ? "2" : y < 10 ? ((x + y) % 2 ? "1" : "2") : y < 13 ? "1" : y === 13 ? "0" : ((x * 3 + y) % 5 === 0 ? "1" : "0");
    const g = grid(24, 18, sky);
    paint(g, kind(code, true), 3 + (index % 3) * 2, 1);
    return rows(g);
}

// The moon at `phase` (0 new, 0.5 full) as a 15x15 disc: lit side light, dark side a sparse dither.
function moon_phase(phase) {
    const size = 15, r = 7.5;
    const k = Math.cos(2 * Math.PI * phase);
    const norm = (x, y) => [(x - 7) / r, (y - 7) / r];
    const inside = (x, y) => sq(norm(x, y)[0]) + sq(norm(x, y)[1]) <= 1;
    const g = grid(size, size, null);
    for (let y = 0; y < size; y++) {
        for (let x = 0; x < size; x++) {
            if (!inside(x, y)) continue;
            const [nx, ny] = norm(x, y);
            const chord = Math.sqrt(Math.max(0, 1 - ny * ny));
            const lit = phase < 0.5 ? nx > k * chord : nx < -k * chord;
            const rim = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1);
            put(g, x, y, rim ? "2" : lit ? "3" : (x + y) % 2 ? "0" : "1");
        }
    }
    return rows(g);
}

// A Clefairy, 20x20, built from overlapping ovals like the clouds: dark rim, light body, tipped ears, curled tail.
function clefairy() {
    const g = grid(20, 20, null);
    const ovals = [
        [10, 9.6, 6.8, 5.4], [10, 15.6, 4.2, 3.2],
        [4.4, 3.6, 2.2, 3.4], [15.6, 3.6, 2.2, 3.4],
        [5.2, 14.8, 1.8, 1.8], [14.8, 14.8, 1.8, 1.8],
        [7.6, 19, 2, 0.9], [12.4, 19, 2, 0.9],
        [17.8, 15.8, 1.6, 1.6]
    ];
    const inside = (x, y) => ovals.some(o => sq((x + 0.5 - o[0]) / o[2]) + sq((y + 0.5 - o[1]) / o[3]) <= 1);
    for (let y = 0; y < 20; y++) {
        for (let x = 0; x < 20; x++) {
            if (!inside(x, y)) continue;
            const rim = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1);
            put(g, x, y, rim ? "0" : y <= 2 && (x < 7 || x > 12) ? "1" : "3");
        }
    }
    // Head tuft, big eyes, cheeks, mouth and a dithered belly.
    [[9, 2], [10, 2], [11, 3], [10, 4], [9, 4]].forEach(p => put(g, p[0], p[1], "0"));
    [[6, 8], [7, 8], [6, 9], [7, 9], [12, 8], [13, 8], [12, 9], [13, 9]].forEach(p => put(g, p[0], p[1], "0"));
    [[6, 8], [12, 8]].forEach(p => put(g, p[0], p[1], "3"));
    [[4, 11], [5, 11], [14, 11], [15, 11]].forEach(p => put(g, p[0], p[1], "2"));
    [[9, 11], [10, 11]].forEach(p => put(g, p[0], p[1], "0"));
    for (let y = 15; y <= 16; y++) for (let x = 8; x <= 11; x++) if ((x + y) % 2 === 0) put(g, x, y, "2");
    put(g, 17, 15, "2");
    return rows(g);
}
