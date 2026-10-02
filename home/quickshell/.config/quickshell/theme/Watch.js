.pragma library

var green = "#4af05c"
var green_dim = "#238a30"
var green_mid = "#3cc04c"
var green_soft = "#2c9a38"
var red = "#ff5a48"
var bar_on = "#3dd84a"
var bar_off = "#1d5a24"
var black = "#000000"
var white = "#e8e8e8"
var rim = "#2e2e2e"
// The aiming crosshair, a little deeper than the skin red so it sits like the game's.
var reticle = "#e23a28"

var head_font = "Michroma"
var mono_font = "Share Tech Mono"
var digit_font = "DSEG7 Classic"

var warm = ["#ff2a10", "#ff4a14", "#ff6a18", "#ff8a22", "#ffa028", "#ffb42c", "#ffc830", "#ffdc34"]
var cold = ["#0c1038", "#101640", "#141c46", "#161d38", "#1a2238", "#1d2538", "#222b3c", "#2a3240"]
var cold_lit = ["#1c2a9a", "#2234a8", "#2a3fb4", "#3350bf", "#3d60c8", "#4a70d0", "#5a82d8", "#6a94e0"]

// Panel gradient stops, top and bottom, as r, g, b, a.
var panel_top = [0, 0.13, 0, 0.8]
var panel_bottom = [0, 0.19, 0.01, 0.8]

function hsl_rgb(h, s, l) {
    const c = (1 - Math.abs(2 * l - 1)) * s
    const hp = (((h % 1) + 1) % 1) * 6
    const x = c * (1 - Math.abs(hp % 2 - 1))
    const m = l - c / 2
    const k = Math.floor(hp)
    const rgb = [[c, x, 0], [x, c, 0], [0, c, x], [0, x, c], [x, 0, c], [c, 0, x]][k % 6]
    return [rgb[0] + m, rgb[1] + m, rgb[2] + m]
}

// How much of the primary hue is mixed into the colorscheme's panel background.
var panel_tint = 0

function mix(a, b, t) {
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
}

function luminance(c) {
    const f = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])
}

function contrast(a, b) {
    const x = luminance(a), y = luminance(b)
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
}

// The lightness of hue/saturation that reaches `target` contrast on `bg`, lighter on a dark backdrop and darker on a light one.
function step_on(hue, s, bg, target) {
    const dark = luminance(bg) < 0.18
    let lo = dark ? 0.3 : 0, hi = dark ? 1 : 0.7
    for (let i = 0; i < 16; i++) {
        const mid = (lo + hi) / 2
        const ok = contrast(hsl_rgb(hue, s, mid), bg) >= target
        if (dark) { if (ok) hi = mid; else lo = mid } else { if (ok) lo = mid; else hi = mid }
    }
    return hsl_rgb(hue, s, dark ? hi : lo)
}

// A colour's saturation for the ramp, 0 for near-greys such as the white lock tint so they stay neutral.
function sat_of(c) {
    return Math.max(c.r, c.g, c.b) - Math.min(c.r, c.g, c.b) < 0.12 ? 0 : c.hslSaturation
}

// The tinted watch from a hue 0-1 and saturation: the panel is the colorscheme background (`top`, `bottom` as [r, g, b]) mixed with `panel_tint` of the hue, translucent over `frame`; text steps are picked for contrast on it.
function theme_ramp(hue, saturation, top, bottom, alpha, frame) {
    const s = saturation <= 0 ? 0 : Math.max(0.3, Math.min(0.85, saturation))
    const base = hsl_rgb(hue, s, 0.5)
    const pt = mix(top, base, panel_tint), pb = mix(bottom, base, panel_tint)
    const over = p => mix(frame, p, alpha)
    const et = over(pt), eb = over(pb)
    const eff = mix(et, eb, 0.5)
    const on = c => step_on(hue, s, eff, c)
    const dim = on(3.4)
    return {
        lit: on(8.2), mid: on(5.6), soft: on(4.2), dim: dim, bar_on: on(6.4), bar_off: mix(eff, base, 0.22),
        panel_top: pt.concat([alpha]), panel_bottom: pb.concat([alpha]), edge: dim.concat([0.45]),
        clock_bg: pt, tile_on: mix(top, base, 0.28), tile_off: mix(top, base, 0.12), light: luminance(eff) >= 0.18
    }
}
