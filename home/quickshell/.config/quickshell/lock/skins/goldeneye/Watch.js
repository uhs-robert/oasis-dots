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

// The tinted watch's text steps, bar and panel colours as [r, g, b] (panels [r, g, b, a]) for a hue 0-1 and saturation; `alpha` is the panel's.
function theme_ramp(hue, saturation, alpha) {
    const s = Math.max(0.3, Math.min(0.85, saturation))
    const d = Math.min(1, s + 0.3)
    const tint = l => hsl_rgb(hue, s, l)
    const deep = l => hsl_rgb(hue, d, l)
    return {
        lit: tint(0.68), mid: tint(0.57), soft: tint(0.48), dim: tint(0.42), bar_on: tint(0.58), bar_off: tint(0.235),
        panel_top: hsl_rgb(hue, d, 0.045).concat([alpha]), panel_bottom: hsl_rgb(hue, d, 0.07).concat([alpha]),
        ink: deep(0.03), mantle: deep(0.05), surface: deep(0.1), clock_bg: deep(0.07), tile_on: deep(0.145), tile_off: deep(0.07)
    }
}
