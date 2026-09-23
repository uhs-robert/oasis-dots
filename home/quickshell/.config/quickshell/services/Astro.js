// home/quickshell/.config/quickshell/services/Astro.js
.pragma library

// Moon position/rise/set math ported from SunCalc (mourner/suncalc, BSD-2-Clause).
const rad = Math.PI / 180;
const day_ms = 1000 * 60 * 60 * 24;
const j2000 = 2451545;
const j1970 = 2440588;
const obliquity = rad * 23.4397;

function to_days(date) {
    return date.valueOf() / day_ms - 0.5 + j1970 - j2000;
}

function right_ascension(l, b) {
    return Math.atan2(Math.sin(l) * Math.cos(obliquity) - Math.tan(b) * Math.sin(obliquity), Math.cos(l));
}

function declination(l, b) {
    return Math.asin(Math.sin(b) * Math.cos(obliquity) + Math.cos(b) * Math.sin(obliquity) * Math.sin(l));
}

function azimuth(h, phi, dec) {
    return Math.atan2(Math.sin(h), Math.cos(h) * Math.sin(phi) - Math.tan(dec) * Math.cos(phi));
}

function altitude(h, phi, dec) {
    return Math.asin(Math.sin(phi) * Math.sin(dec) + Math.cos(phi) * Math.cos(dec) * Math.cos(h));
}

function sidereal_time(d, lw) {
    return rad * (280.16 + 360.9856235 * d) - lw;
}

function hours_later(date, h) {
    return new Date(date.valueOf() + h * day_ms / 24);
}

function moon_coords(d) {
    const l_ecl = rad * (218.316 + 13.176396 * d);
    const m_anom = rad * (134.963 + 13.064993 * d);
    const f_dist = rad * (93.272 + 13.229350 * d);
    const l = l_ecl + rad * 6.289 * Math.sin(m_anom);
    const b = rad * 5.128 * Math.sin(f_dist);
    const dt = 385001 - 20905 * Math.cos(m_anom);
    return { ra: right_ascension(l, b), dec: declination(l, b), dist: dt };
}

function moon_position(date, lat, lng) {
    const d = to_days(date);
    const c = moon_coords(d);
    const lw = rad * -lng;
    const phi = rad * lat;
    const h_angle = sidereal_time(d, lw) - c.ra;
    let h = altitude(h_angle, phi, c.dec);
    h = h + rad * 0.017 / Math.tan(h + rad * 10.26 / (h + rad * 5.10));
    return { azimuth: azimuth(h_angle, phi, c.dec), altitude: h, distance: c.dist };
}

// Returns { rise, set } as Date objects (UTC instants), or { alwaysUp: true } / { alwaysDown: true }.
function moon_times(date, lat, lng) {
    const t = new Date(date);

    const hc = 0.133 * rad;
    let h0 = moon_position(t, lat, lng).altitude - hc;
    let rise, set, ye = 0;

    for (let i = 1; i <= 24; i += 2) {
        const h1 = moon_position(hours_later(t, i), lat, lng).altitude - hc;
        const h2 = moon_position(hours_later(t, i + 1), lat, lng).altitude - hc;

        const a = (h0 + h2) / 2 - h1;
        const b = (h2 - h0) / 2;
        const xe = -b / (2 * a);
        ye = (a * xe + b) * xe + h1;
        const disc = b * b - 4 * a * h1;
        let roots = 0;
        let x1, x2;

        if (disc >= 0) {
            const dx = Math.sqrt(disc) / (Math.abs(a) * 2);
            x1 = xe - dx;
            x2 = xe + dx;
            if (Math.abs(x1) <= 1) roots++;
            if (Math.abs(x2) <= 1) roots++;
            if (x1 < -1) x1 = x2;
        }

        if (roots === 1) {
            if (h0 < 0) rise = i + x1;
            else set = i + x1;
        } else if (roots === 2) {
            rise = i + (ye < 0 ? x2 : x1);
            set = i + (ye < 0 ? x1 : x2);
        }

        if (rise !== undefined && set !== undefined) break;
        h0 = h2;
    }

    const result = {};
    if (rise !== undefined) result.rise = hours_later(t, rise);
    if (set !== undefined) result.set = hours_later(t, set);
    if (rise === undefined && set === undefined) result[ye > 0 ? "alwaysUp" : "alwaysDown"] = true;
    return result;
}
