.pragma library

// Monitors in rows: a monitor starts a new row once it sits below every monitor already in the row.
function flat(list) {
    return [].concat(...list);
}

function bands(groups) {
    const order = groups.map((g, i) => i).sort((a, b) => groups[a].y - groups[b].y || groups[a].x - groups[b].x);
    const out = [];
    let bottom = -Infinity;
    for (const i of order) {
        const g = groups[i];
        if (out.length === 0 || g.y >= bottom) {
            out.push([i]);
            bottom = g.y + g.h;
        } else {
            out[out.length - 1].push(i);
            bottom = Math.min(bottom, g.y + g.h);
        }
    }
    return out.map(band => band.sort((a, b) => groups[a].x - groups[b].x));
}

function aspect(g) {
    return g.h > 0 ? g.w / g.h : 16 / 9;
}

function empty(groups, tiles) {
    return { group_rects: groups.map(() => ({ x: 0, y: 0, w: 0, h: 0 })), tile_rects: tiles.map(() => ({ x: 0, y: 0, w: 0, h: 0 })), big: null, order: [] };
}

// Groups placed like the real monitors, each a grid of tiles; m holds gap, pad, label and group_gap.
function minimap(groups, area_w, area_h, m) {
    const rows_of = bands(groups);
    let best = null;
    const max_n = Math.max(1, ...groups.map(g => g.tiles.length));
    for (let r = 1; r <= Math.min(3, max_n); r++) {
        const cols = groups.map(g => Math.max(1, Math.ceil(g.tiles.length / r)));
        const rows = groups.map((g, i) => Math.max(1, Math.ceil(g.tiles.length / cols[i])));
        let h = area_h * 0.45;
        for (const band of rows_of) {
            let fixed = (band.length - 1) * m.group_gap;
            let per = 0;
            for (const i of band) {
                fixed += 2 * m.pad + (cols[i] - 1) * m.gap;
                per += cols[i] * aspect(groups[i]);
            }
            h = Math.min(h, (area_w - fixed) / per);
        }
        let fixed_v = (rows_of.length - 1) * m.group_gap;
        let per_v = 0;
        for (const band of rows_of) {
            const rb = Math.max(...band.map(i => rows[i]));
            fixed_v += 2 * m.pad + m.label + (rb - 1) * m.gap;
            per_v += rb;
        }
        h = Math.min(h, (area_h - fixed_v) / per_v);
        if (!best || h > best.h) best = { h: h, cols: cols, rows: rows };
    }
    const th = Math.max(8, best.h);
    const gw = groups.map((g, i) => best.cols[i] * aspect(g) * th + (best.cols[i] - 1) * m.gap + 2 * m.pad);
    const gh = groups.map((g, i) => best.rows[i] * th + (best.rows[i] - 1) * m.gap + 2 * m.pad + m.label);
    const min_x = Math.min(...groups.map(g => g.x));
    const real_w = Math.max(1, Math.max(...groups.map(g => g.x + g.w)) - min_x);
    const band_h = rows_of.map(band => Math.max(...band.map(i => gh[i])));
    const total_h = band_h.reduce((a, b) => a + b, 0) + (rows_of.length - 1) * m.group_gap;
    const out = empty(groups, flat(groups.map(g => g.tiles)));
    let y = Math.max(0, (area_h - total_h) / 2);
    rows_of.forEach((band, b) => {
        const xs = [];
        let right = -Infinity;
        for (const i of band) {
            const want = ((groups[i].x + groups[i].w / 2 - min_x) / real_w) * area_w - gw[i] / 2;
            const x = Math.max(want, right + m.group_gap, 0);
            xs.push(x);
            right = x + gw[i];
        }
        const shift = Math.max(0, right - area_w);
        band.forEach((i, k) => {
            const gx = Math.max(0, xs[k] - shift);
            const gy = y + (band_h[b] - gh[i]) / 2;
            out.group_rects[i] = { x: gx, y: gy, w: gw[i], h: gh[i] };
            const tw = aspect(groups[i]) * th;
            groups[i].tiles.forEach((t, j) => {
                const c = j % best.cols[i];
                const r = Math.floor(j / best.cols[i]);
                out.tile_rects[t] = { x: gx + m.pad + c * (tw + m.gap), y: gy + m.pad + m.label + r * (th + m.gap), w: tw, h: th };
            });
        });
        y += band_h[b] + m.group_gap;
    });
    return out;
}

// One full-width row per monitor, in mini-map reading order, its name in a column on the left.
function rows(groups, area_w, area_h, m) {
    const order = flat(bands(groups));
    const n = Math.max(1, order.length);
    let th = (area_h - (n - 1) * m.group_gap - n * 2 * m.pad) / n;
    for (const i of order) {
        const k = Math.max(1, groups[i].tiles.length);
        th = Math.min(th, (area_w - 2 * m.pad - m.label_col - (k - 1) * m.gap) / (k * aspect(groups[i])));
    }
    th = Math.max(8, th);
    const gh = th + 2 * m.pad;
    const total_h = n * gh + (n - 1) * m.group_gap;
    const out = empty(groups, flat(groups.map(g => g.tiles)));
    let y = Math.max(0, (area_h - total_h) / 2);
    for (const i of order) {
        out.group_rects[i] = { x: 0, y: y, w: area_w, h: gh };
        const tw = aspect(groups[i]) * th;
        groups[i].tiles.forEach((t, j) => {
            out.tile_rects[t] = { x: m.pad + m.label_col + j * (tw + m.gap), y: y + m.pad, w: tw, h: th };
        });
        y += gh + m.group_gap;
    }
    return out;
}

// Every workspace in one strip along the bottom, scrolled to the selection, which also shows large above it.
function filmstrip(groups, area_w, area_h, m, tiles, selected) {
    const order = flat(bands(groups));
    const strip_h = Math.max(48, Math.min(m.strip, area_h * 0.22));
    const th = strip_h - m.label - m.pad;
    const out = empty(groups, tiles);
    let x = 0;
    const spans = {};
    order.forEach((i, k) => {
        if (k > 0) x += m.group_gap;
        const start = x;
        const tw = aspect(groups[i]) * th;
        groups[i].tiles.forEach((t, j) => {
            if (j > 0) x += m.gap;
            out.tile_rects[t] = { x: x, y: area_h - th, w: tw, h: th };
            out.order.push(t);
            x += tw;
        });
        spans[i] = { start: start, end: x };
    });
    const sel = out.tile_rects[selected];
    let offset = (area_w - x) / 2;
    if (x > area_w && sel) offset = Math.min(0, Math.max(area_w - x, area_w / 2 - (sel.x + sel.w / 2)));
    for (const t of out.order) out.tile_rects[t].x += offset;
    for (const i of order) out.group_rects[i] = { x: spans[i].start + offset, y: area_h - strip_h, w: spans[i].end - spans[i].start, h: strip_h };
    if (sel && tiles[selected]) {
        const g = groups[tiles[selected].group];
        const room_h = area_h - strip_h - m.group_gap;
        const a = aspect(g);
        const bw = Math.min(area_w, room_h * a);
        const bh = bw / a;
        out.big = { x: (area_w - bw) / 2, y: Math.max(0, (room_h - bh) / 2), w: bw, h: bh };
    }
    return out;
}

function compute(draft, groups, tiles, area_w, area_h, m, selected) {
    if (groups.length === 0 || area_w <= 0 || area_h <= 0) return empty(groups, tiles);
    if (draft === 2) return rows(groups, area_w, area_h, m);
    if (draft === 3) return filmstrip(groups, area_w, area_h, m, tiles, selected);
    return minimap(groups, area_w, area_h, m);
}

// The nearest tile whose center lies in direction (dx, dy), favouring ones in line with the current tile.
function neighbor(rects, from, dx, dy) {
    const a = rects[from];
    if (!a) return -1;
    const ax = a.x + a.w / 2, ay = a.y + a.h / 2;
    let best = -1, best_score = Infinity;
    rects.forEach((r, i) => {
        if (i === from || r.w <= 0) return;
        const cx = r.x + r.w / 2 - ax, cy = r.y + r.h / 2 - ay;
        const along = dx !== 0 ? cx * dx : cy * dy;
        const across = dx !== 0 ? Math.abs(cy) : Math.abs(cx);
        if (along <= 1) return;
        const overlap = dx !== 0 ? r.y < a.y + a.h && r.y + r.h > a.y : r.x < a.x + a.w && r.x + r.w > a.x;
        const score = along + across * (overlap ? 0.5 : 3);
        if (score < best_score) {
            best_score = score;
            best = i;
        }
    });
    return best;
}

// Brings a ListModel's `key` rows in line with keys: gone ones removed, new ones appended, the rest left alive.
function sync_keys(list_model, keys) {
    const want = {};
    for (const k of keys) want[k] = true;
    const have = {};
    for (let i = list_model.count - 1; i >= 0; i--) {
        const k = list_model.get(i).key;
        if (want[k] && !have[k]) have[k] = true;
        else list_model.remove(i);
    }
    const add = keys.filter(k => !have[k]).map(k => ({ key: k }));
    if (add.length > 0) list_model.append(add);
}
