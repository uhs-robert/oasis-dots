.pragma library
.import "IslandOutlines.js" as Outlines

// The corner profiles of the screen frame's hole and of the drawers that join it: how a corner between two
// perpendicular edges is drawn. Pure geometry, so FrameGeometry and DrawerGeometry share it and node can test it.

const kinds = ["round", "chamfer", "pixel", "square"];

// The largest corner each profile draws, so a tiled window with square corners never pokes past the cut. A
// round corner is not capped: Hyprland rounds the windows to match it.
const CHAMFER_MAX = 12;
const PIXEL_MAX = 18;
// More stairs than this stop reading as pixels, so the stair grows its step instead.
const MAX_STAIRS = 8;

function valid(kind) {
    return kinds.indexOf(kind) >= 0 ? kind : "round";
}

// What a requested corner of size `r` and stair step `step` draws: { radius, step, stairs }. The pixel radius is a whole
// number of whole-pixel steps (`stairs` of them), never above `r`, so every stair vertex lands on a pixel. A corner too
// small for one step is square.
function fit(kind, r, step) {
    kind = valid(kind);
    if (!(r > 0) || kind === "square") return { radius: 0, step: 0, stairs: 0 };
    if (kind === "round") return { radius: r, step: 0, stairs: 0 };
    if (kind === "chamfer") return { radius: Math.min(r, CHAMFER_MAX), step: 0, stairs: 0 };
    const cap = Math.min(Math.floor(r), PIXEL_MAX);
    let s = step >= 1 ? Math.round(step) : 1;
    if (Math.floor(cap / s) > MAX_STAIRS) s = Math.ceil(cap / MAX_STAIRS);
    const stairs = Math.floor(cap / s);
    if (stairs < 1) return { radius: 0, step: 0, stairs: 0 };
    return { radius: stairs * s, step: s, stairs: stairs };
}

// A colour as the "rgba(rrggbbaa)" string Hyprland parses, from Qt's 0 to 1 channels.
function hypr_color(c) {
    const hex = v => ("0" + Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)).slice(-2);
    return "rgba(" + hex(c.r) + hex(c.g) + hex(c.b) + hex(c.a) + ")";
}

// The corner between two edges as a polyline, from the point where the first edge ends to where the second begins.
// (cx, cy), r, a0 and a1 are the quarter circle a round corner draws (IslandOutlines.arc); the other profiles use its
// two ends and the square corner opposite its centre, so a caller swaps profiles without moving a join. `r` must
// already be fit() to the profile.
function corner_points(kind, r, step, cx, cy, a0, a1) {
    kind = valid(kind);
    if (kind === "round") return Outlines.arc(cx, cy, r, a0, a1);
    const at = a => [cx + r * Math.round(Math.cos(a * Math.PI / 180)), cy + r * Math.round(Math.sin(a * Math.PI / 180))];
    const s = at(a0), e = at(a1);
    const q = [s[0] + e[0] - cx, s[1] + e[1] - cy];
    if (kind === "square" || !(r > 0)) return [q];
    if (kind === "chamfer") return [s, e];
    // The stair, as offsets from q along the unit vectors toward each end: down to the first end's side first, so each
    // end's first step runs perpendicular to the edge it leaves.
    const n = Math.round(r / step), w = r / n;
    const ex = [(s[0] - q[0]) / r, (s[1] - q[1]) / r], ey = [(e[0] - q[0]) / r, (e[1] - q[1]) / r];
    const local = [];
    for (let i = 0; i < n; i++) local.push([(n - i) * w, i * w], [(n - i) * w, (i + 1) * w]);
    local.push([0, n * w]);
    return local.map(p => [q[0] + p[0] * ex[0] + p[1] * ey[0], q[1] + p[0] * ex[1] + p[1] * ey[1]]);
}
