// home/quickshell/.config/quickshell/popups/weather/Materia.js
.pragma library

// WeatherState color keys folded into the style's materia kinds.
const kinds = {
    clear: "clear",
    partly_cloudy: "cloud",
    overcast: "cloud",
    fog: "fog",
    drizzle: "rain",
    rain: "rain",
    heavy_rain: "rain",
    freezing_rain: "rain",
    snow: "snow",
    heavy_snow: "snow",
    thunderstorm: "storm"
};

function kind(color_keys, code) {
    return kinds[color_keys[Math.round(code)]] || "cloud";
}

function color(materia, color_keys, code) {
    return materia[kind(color_keys, code)] || materia.cloud || "transparent";
}

const colors = ["red", "green", "purple", "blue", "yellow"];
// Each date's color walks this cycle; blue sits between its only partners, so a linked pair rarely breaks the rule.
const cycle = ["green", "blue", "purple", "red", "yellow"];
const blue_partners = ["green", "purple"];

function epoch_day(date) {
    const p = String(date).split("-").map(Number);
    return Math.round(Date.UTC(p[0], p[1] - 1, p[2]) / 86400000);
}

function linked_ok(combo) {
    const linked = combo.length - combo.length % 2;
    for (let i = 0; i < combo.length; i++) {
        if (combo[i] === "blue" && (i >= linked || blue_partners.indexOf(combo[i ^ 1]) < 0)) return false;
    }
    return true;
}

// A unique color name per date in slots linked 0-1, 2-3; each date keeps its cycle color wherever blue's pairing allows.
function day_colors(dates) {
    const want = dates.map(d => cycle[((epoch_day(d) % 5) + 5) % 5]);
    let best = [];
    let best_kept = -1;
    const walk = combo => {
        if (combo.length === dates.length) {
            const kept = combo.filter((c, i) => c === want[i]).length;
            if (kept > best_kept && linked_ok(combo)) {
                best = combo.slice();
                best_kept = kept;
            }
            return;
        }
        for (const c of colors) {
            if (combo.indexOf(c) >= 0) continue;
            combo.push(c);
            walk(combo);
            combo.pop();
        }
    };
    if (dates.length <= colors.length) walk([]);
    return best;
}

const compass = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];

function direction(deg) {
    return compass[Math.round(((deg % 360) + 360) % 360 / 22.5) % 16];
}
