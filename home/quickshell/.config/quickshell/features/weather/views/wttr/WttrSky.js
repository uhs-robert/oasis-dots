.pragma library

const ramp = " .:-=+*#%@";
// Dark patches (maria) as [x, y, radius] in unit-disc coordinates.
const maria = [[-0.28, -0.22, 0.3], [0.18, -0.4, 0.2], [0.32, 0.18, 0.26], [-0.1, 0.35, 0.16]];

// The moon as a disc of rows by cols characters (cols about rows times the cell's height-to-width ratio). Returns lines of [text, key] runs, key "b" bright, "m" mid, "d" dim.
// phase 0 is new, 0.5 full; the waxing moon is lit on the right.
function moon_art(phase, rows, cols) {
    const turn = Math.cos(2 * Math.PI * phase);
    const waxing = phase < 0.5;
    const lines = [];
    for (let r = 0; r < rows; r++) {
        const runs = [];
        for (let c = 0; c < cols; c++) {
            const nx = (c + 0.5 - cols / 2) / (cols / 2);
            const ny = (r + 0.5 - rows / 2) / (rows / 2);
            const radius_sq = nx * nx + ny * ny;
            let ch = " ";
            let key = "d";
            if (radius_sq <= 1) {
                const half_w = Math.sqrt(1 - ny * ny);
                const edge = waxing ? nx - turn * half_w : -turn * half_w - nx;
                const lit = Math.min(1, Math.max(0, edge / 0.3));
                let shade = lit * (1 - 0.3 * radius_sq);
                for (const m of maria) {
                    const d = Math.hypot(nx - m[0], ny - m[1]);
                    if (d < m[2]) shade *= 0.55 + 0.45 * (d / m[2]);
                }
                const level = Math.min(9, Math.floor(shade * 10));
                if (level > 0) {
                    ch = ramp[level];
                    key = level >= 7 ? "b" : level >= 4 ? "m" : "d";
                } else if (radius_sq > 0.72) {
                    ch = ".";
                }
            }
            if (runs.length > 0 && (runs[runs.length - 1][1] === key || ch === " ")) runs[runs.length - 1][0] += ch;
            else runs.push([ch, key]);
        }
        lines.push(runs);
    }
    return lines;
}

function illumination(phase) {
    return (1 - Math.cos(2 * Math.PI * phase)) / 2;
}

// Civil dawn and dusk in minutes since midnight, scaled from the forecast's own sunrise and sunset so the
// two stay consistent; null where the sun never reaches -6 degrees or the location is unknown.
function civil_twilight(lat, lon, date_str, rise_min, set_min) {
    // (0, 0) is how WeatherState marks an unknown location, as in moon_times_for_date.
    if ((lat === 0 && lon === 0) || rise_min === null || set_min === null || set_min <= rise_min) return null;
    const rad = Math.PI / 180;
    const day_of_year = Math.floor((Date.parse(date_str + "T00:00:00Z") - Date.parse(date_str.slice(0, 4) + "-01-01T00:00:00Z")) / 86400000) + 1;
    const dec = 23.44 * rad * Math.sin(2 * Math.PI * (284 + day_of_year) / 365);
    const hour_angle = alt => {
        const c = (Math.sin(alt * rad) - Math.sin(lat * rad) * Math.sin(dec)) / (Math.cos(lat * rad) * Math.cos(dec));
        return Math.abs(c) > 1 ? null : Math.acos(c);
    };
    const at_rise = hour_angle(-0.833);
    const at_dawn = hour_angle(-6);
    if (at_rise === null || at_dawn === null || at_rise === 0) return null;
    const noon = (rise_min + set_min) / 2;
    const reach = (set_min - rise_min) / 2 * at_dawn / at_rise;
    return { dawn: noon - reach, dusk: noon + reach };
}
