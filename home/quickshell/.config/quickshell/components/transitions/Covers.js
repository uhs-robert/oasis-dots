.pragma library

function seg(t, a, b) {
    return Math.max(0, Math.min(1, (t - a) / (b - a)));
}

function ease_out(x) {
    return 1 - (1 - x) * (1 - x);
}

function ease_in_out(x) {
    return x < 0.5 ? 2 * x * x : 1 - Math.pow(-2 * x + 2, 2) / 2;
}

function hash(i, j) {
    const s = Math.sin(i * 127.1 + j * 311.7) * 43758.5453;
    return s - Math.floor(s);
}

function box(ctx, x, y, w, h) {
    if (w > 0 && h > 0) ctx.fillRect(x, y, w, h);
}

// Adds an ellipse wound against rect(), so a nonzero fill leaves it as a hole.
function hole(ctx, cx, cy, rx, ry) {
    const n = 72;
    ctx.moveTo(cx + rx, cy);
    for (let i = 1; i <= n; i++) {
        const a = -2 * Math.PI * i / n;
        ctx.lineTo(cx + rx * Math.cos(a), cy + ry * Math.sin(a));
    }
    ctx.closePath();
}

function ellipse_path(ctx, cx, cy, rx, ry) {
    ctx.beginPath();
    hole(ctx, cx, cy, rx, ry);
}

function cover_except(ctx, w, h, c, cx, cy, rx, ry) {
    ctx.fillStyle = c.cover;
    ctx.beginPath();
    ctx.rect(0, 0, w, h);
    if (rx > 0 && ry > 0) hole(ctx, cx, cy, rx, ry);
    ctx.fill();
}

// NES: blocks dissolve left to right in stepped frames, a primary-coloured edge leading.
function blocks(ctx, t, d, w, h, c) {
    const cell = Math.max(4, Math.round(h / 4));
    const cols = Math.ceil(w / cell);
    const rows = Math.ceil(h / cell);
    const q = (Math.floor(t / 50) * 50 / d) * 1.12 - 0.08;
    for (let i = 0; i < cols; i++) {
        for (let j = 0; j < rows; j++) {
            const th = 0.75 * i / cols + 0.25 * hash(i, j);
            if (th <= q) continue;
            ctx.fillStyle = th < q + 0.06 ? c.primary : c.cover;
            ctx.fillRect(i * cell, j * cell, cell, cell);
        }
    }
}

// PS2: translucent towers rise at random from the bottom, then the dark fades.
function towers(ctx, t, d, w, h, c) {
    const fade = 1 - ease_out(seg(t, 0.5 * d, d));
    ctx.globalAlpha = fade;
    ctx.fillStyle = c.cover;
    ctx.fillRect(0, 0, w, h);
    const step = Math.max(8, Math.round(h * 0.45));
    const tw = Math.max(3, Math.round(step * 0.55));
    for (let i = 0, x = Math.round((step - tw) / 2); x < w; i++, x += step) {
        const delay = hash(i, 1) * 0.35 * d;
        const th = Math.round(h * (0.35 + 0.65 * hash(i, 2)) * ease_out(seg(t, delay, delay + 0.3 * d)));
        if (th <= 0) continue;
        ctx.globalAlpha = fade * 0.55;
        ctx.fillStyle = c.primary;
        ctx.fillRect(x, h - th, tw, th);
        ctx.globalAlpha = fade;
        ctx.fillStyle = c.strong;
        ctx.fillRect(x, h - th, tw, Math.min(2, th));
    }
}

// Metroid: a scanline sweeps the dark visor, it opens from the centre and the reticle blinks.
function visor(ctx, t, d, w, h, c) {
    const cx = w / 2;
    const half = ease_in_out(seg(t, 0.3 * d, 0.85 * d)) * (cx + 2);
    const edge_a = 1 - seg(t, 0.8 * d, d);
    ctx.fillStyle = c.cover;
    box(ctx, 0, 0, cx - half, h);
    box(ctx, cx + half, 0, w - cx - half, h);
    ctx.globalAlpha = 0.12;
    ctx.fillStyle = c.primary;
    for (let y = 1; y < h; y += 3) {
        box(ctx, 0, y, cx - half, 1);
        box(ctx, cx + half, y, w - cx - half, 1);
    }
    if (t < 0.3 * d) {
        const y = Math.round(seg(t, 0, 0.3 * d) * h);
        ctx.globalAlpha = 0.35;
        ctx.fillRect(0, y - 4, w, 4);
        ctx.globalAlpha = 0.9;
        ctx.fillRect(0, y, w, 2);
    }
    if (half > 0) {
        ctx.globalAlpha = edge_a;
        ctx.fillStyle = c.primary;
        ctx.fillRect(cx - half - 2, 0, 2, h);
        ctx.fillRect(cx + half, 0, 2, h);
    }
    const blink = [[0.2, 0.3], [0.42, 0.52], [0.62, 0.92]].some(b => t >= b[0] * d && t < b[1] * d);
    if (!blink) return;
    const r = h * 0.32;
    const cy = h / 2;
    ctx.globalAlpha = 1;
    ctx.strokeStyle = c.primary;
    ctx.lineWidth = 1.5;
    ellipse_path(ctx, cx, cy, r, r);
    ctx.stroke();
    ctx.beginPath();
    for (const s of [-1, 1]) {
        ctx.moveTo(cx + s * (r - 2), cy);
        ctx.lineTo(cx + s * (r + 6), cy);
        ctx.moveTo(cx, cy + s * (r - 2));
        ctx.lineTo(cx, cy + s * (r + 4));
    }
    ctx.stroke();
}

// GoldenEye: gun-barrel dots cross to the centre, the iris closes on the old look and opens on the new.
function iris(ctx, t, cover, reveal, w, h, c) {
    const cx = w / 2;
    const cy = h / 2;
    const r0 = Math.max(2, h * 0.2);
    const far = cx + h;
    const radius = t < cover ? (1 - ease_in_out(seg(t, 0.5 * cover, cover))) * far : ease_in_out(seg(t, cover, cover + reveal)) * far;
    if (t >= 0.5 * cover) {
        cover_except(ctx, w, h, c, cx, cy, radius, radius);
        ctx.globalAlpha = 1 - radius / far;
        ctx.strokeStyle = c.dim;
        ctx.lineWidth = Math.max(2, h * 0.12);
        ellipse_path(ctx, cx, cy, Math.max(r0, radius), Math.max(r0, radius));
        ctx.stroke();
    }
    ctx.globalAlpha = t < cover ? 1 : 1 - seg(t, cover, cover + 0.3 * reveal);
    ctx.fillStyle = c.strong;
    const lead = ease_in_out(seg(t, 0, 0.5 * cover)) * cx;
    for (let k = 0; k < 3; k++) {
        const x = lead - k * h * 1.1 * (1 - seg(t, 0.35 * cover, 0.5 * cover));
        if (x < -r0 || (k > 0 && t >= 0.5 * cover)) continue;
        ellipse_path(ctx, x, cy, r0, r0);
        ctx.fill();
    }
}

// TIE: a targeting sweep runs left to right, leaving a fading grid behind it.
function grid(ctx, t, d, w, h, c) {
    const xs = ease_in_out(seg(t, 0, d)) * (w + 40) - 20;
    const g = Math.max(8, Math.round(h * 0.5));
    const trail = 180;
    ctx.fillStyle = c.cover;
    box(ctx, xs, 0, w - xs, h);
    ctx.fillStyle = c.primary;
    for (let x = 0; x < w; x += g) {
        ctx.globalAlpha = x >= xs ? 0.18 : 0.6 * Math.max(0, 1 - (xs - x) / trail);
        if (ctx.globalAlpha > 0) ctx.fillRect(x, 0, 1, h);
    }
    ctx.globalAlpha = 1;
    for (const y of [Math.round(h / 3), Math.round(2 * h / 3)]) {
        const grad = ctx.createLinearGradient(xs - trail, 0, xs, 0);
        grad.addColorStop(0, c.primary_clear);
        grad.addColorStop(1, c.primary);
        ctx.fillStyle = grad;
        ctx.fillRect(xs - trail, y, trail, 1);
    }
    ctx.globalAlpha = 0.35;
    ctx.fillStyle = c.primary;
    ctx.fillRect(xs - 4, 0, 8, h);
    ctx.globalAlpha = 1;
    ctx.fillStyle = c.strong;
    ctx.fillRect(xs - 1, 0, 2, h);
}

// Oblivion and Mech: accent lines trace out from the centre along both edges, then the dark lifts.
function trace(ctx, t, d, w, h, c) {
    const cx = w / 2;
    const half = ease_out(seg(t, 0, 0.55 * d)) * cx;
    const line_a = 1 - seg(t, 0.7 * d, d);
    ctx.globalAlpha = 1 - ease_out(seg(t, 0.45 * d, d));
    ctx.fillStyle = c.cover;
    ctx.fillRect(0, 0, w, h);
    ctx.globalAlpha = line_a;
    ctx.fillStyle = c.accent;
    ctx.fillRect(cx - half, 0, 2 * half, 2);
    ctx.fillRect(cx - half, h - 2, 2 * half, 2);
    ctx.globalAlpha = line_a * 0.8;
    const tick = Math.max(3, Math.round(h * 0.25));
    for (let x = cx % 24; x < w; x += 24) {
        if (Math.abs(x - cx) <= half) ctx.fillRect(x, h - tick, 1, tick);
    }
    if (half < cx) {
        ctx.globalAlpha = 1;
        ctx.fillStyle = c.strong;
        ctx.fillRect(cx - half - 2, 0, 4, 3);
        ctx.fillRect(cx + half - 2, 0, 4, 3);
        ctx.fillRect(cx - half - 2, h - 3, 4, 3);
        ctx.fillRect(cx + half - 2, h - 3, 4, 3);
    }
}

// Terminal and Neovim: a block cursor types the bar in one cell at a time.
function cursor(ctx, t, d, w, h, c) {
    const cw = c.cell;
    const steps = Math.ceil(w / cw);
    const pos = Math.min(steps, Math.floor(seg(t, 0, 0.85 * d) * steps));
    const x = pos * cw;
    ctx.fillStyle = c.cover;
    box(ctx, x + cw, 0, w - x - cw, h);
    if (pos < steps) {
        ctx.fillStyle = c.caret;
        ctx.fillRect(x, 0, cw, h);
    }
}

// Oasis: a sun rises at the centre and daylight spreads outward from the horizon.
function sunrise(ctx, t, d, w, h, c) {
    const cx = w / 2;
    const o = ease_in_out(seg(t, 0.25 * d, d));
    const rx = o * (cx * 1.15 + h);
    const ry = Math.min(rx, h * 2.2);
    cover_except(ctx, w, h, c, cx, h, rx, ry);
    ctx.globalAlpha = 1 - seg(t, 0.6 * d, d);
    ctx.fillStyle = c.secondary;
    ctx.fillRect(0, h - 1, w, 1);
    if (rx > 0) {
        ctx.strokeStyle = c.secondary;
        ctx.lineWidth = 2;
        ellipse_path(ctx, cx, h, rx, ry);
        ctx.stroke();
    }
    const r = h * 0.4;
    const sy = h + r - ease_out(seg(t, 0, 0.35 * d)) * (r + h * 0.4);
    const sun_a = 1 - seg(t, 0.5 * d, 0.9 * d);
    ctx.globalAlpha = 0.3 * sun_a;
    ellipse_path(ctx, cx, sy, r * 1.8, r * 1.8);
    ctx.fill();
    ctx.globalAlpha = sun_a;
    ellipse_path(ctx, cx, sy, r, r);
    ctx.fill();
}

const painters = { blocks: blocks, towers: towers, visor: visor, grid: grid, trace: trace, cursor: cursor, sunrise: sunrise };

// The cover half plays a kind's reveal in reverse; iris has its own two halves.
function paint(ctx, kind, t, cover, reveal, w, h, c) {
    ctx.save();
    ctx.clearRect(0, 0, w, h);
    if (kind === "iris") {
        iris(ctx, t, cover, reveal, w, h, c);
    } else {
        const fn = painters[kind];
        const r = t < cover ? reveal * (1 - t / cover) : t - cover;
        if (fn) fn(ctx, r, reveal, w, h, c);
    }
    ctx.restore();
}
