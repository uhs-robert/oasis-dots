.pragma library

// Named weather states for testing. Every object is shaped like the ones WeatherState builds
// (parse_blob, handle_air_quality, handle_alerts), so a view cannot tell a fixture from a fetch.
// A fixture patches the fields it names and leaves the rest; "base" is the synthetic full state
// the offscreen renderer starts from so renders do not depend on the network or the clock.

const names = ["base", "alerts1", "alerts3", "aqi-bad", "rain", "night"];

const hour_ms = 3600000;
const day_ms = 24 * hour_ms;

function iso_in(now, offset_ms) {
    return new Date(now + offset_ms).toISOString();
}

function pad2(n) {
    return n < 10 ? "0" + n : "" + n;
}

// Location clock is UTC (utc_offset 0) in the synthetic base.
function make_hour(now, i) {
    const t = Math.ceil(now / hour_ms) * hour_ms + i * hour_ms;
    const d = new Date(t);
    const hour = d.getUTCHours();
    const day = hour >= 6 && hour < 20;
    const temp = 58 + 16 * Math.sin((hour - 9) / 24 * 2 * Math.PI);
    return {
        dt: d.toISOString(),
        date: d.toISOString().substr(0, 10),
        hour: hour,
        temp: Math.round(temp * 10) / 10,
        feels: Math.round((temp - 2) * 10) / 10,
        pop: 5,
        precip: 0,
        code: day ? 1 : 0,
        is_day: day ? 1 : 0,
        cond: day ? "Mainly clear" : "Clear sky",
        humidity: 55 + Math.round(15 * Math.cos(hour / 24 * 2 * Math.PI)),
        uv_index: day ? Math.max(0, Math.round(8 * Math.sin((hour - 6) / 14 * Math.PI) * 10) / 10) : 0,
        wind_speed: 6 + (i % 7),
        wind_dir: (200 + i * 5) % 360,
        wind_gusts: 12 + (i % 9)
    };
}

function make_day(now, i) {
    const d = new Date(Math.floor(now / day_ms) * day_ms + i * day_ms);
    const date = d.toISOString().substr(0, 10);
    return {
        date: date,
        weekday: i === 0 ? "Today" : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getUTCDay()],
        min: 52 + (i % 3) * 2,
        max: 74 + ((i * 3) % 7),
        code: 1,
        cond: "Mainly clear",
        pop: 10,
        precip: 0,
        sunrise: "06:" + pad2(40 + i),
        sunset: "19:" + pad2(20 - i),
        uv_max: 6 + (i % 3),
        wind_speed_max: 10 + i,
        wind_gusts_max: 20 + i,
        wind_dir: 210,
        sunshine_hours: 9 - (i % 3)
    };
}

function base(now) {
    const hours = [];
    for (let i = 0; i < 72; i++) hours.push(make_hour(now, i));
    const days = [];
    for (let i = 0; i < 7; i++) days.push(make_day(now, i));
    const h0 = hours[0];
    return {
        current: {
            temp: h0.temp, feels: h0.feels, code: h0.code, is_day: h0.is_day, precip: 0, cond: h0.cond,
            humidity: h0.humidity, dew_point: 48, pressure: 1014, visibility: 24140, uv_index: h0.uv_index,
            cloud_cover: 20, wind_speed: h0.wind_speed, wind_dir: h0.wind_dir, wind_gusts: h0.wind_gusts
        },
        hours: hours,
        days: days,
        location_name: "Fixture City",
        updated: now,
        sunrise: days[0].sunrise,
        sunset: days[0].sunset,
        utc_offset: 0,
        data_unit: "fahrenheit",
        aq_current: { aqi: 42, pm25: 9.1, pm10: 14.3, ozone: 61 },
        aq_hours: hours.slice(0, 24).map((h, i) => ({ dt: h.dt, aqi: 38 + (i % 6) * 3 })),
        aq_has_data: true,
        alerts: [],
        alerts_has_data: true
    };
}

const alert_pool = {
    tornado: {
        event: "Tornado Warning",
        severity: "Extreme",
        urgency: "Immediate",
        headline: "Tornado Warning issued for Fixture County until the evening by NWS Fixture City",
        description: "At the time of this warning, a severe thunderstorm capable of producing a tornado was located near the county seat, moving northeast at 35 mph.\n\nHAZARD...Tornado and golf ball size hail.\n\nSOURCE...Radar indicated rotation.\n\nIMPACT...Flying debris will be dangerous to those caught without shelter. Mobile homes will be damaged or destroyed. Damage to roofs, windows, and vehicles will occur. Tree damage is likely.\n\nThis dangerous storm will be near Fixture City and the surrounding lowlands within the half hour.",
        instruction: "TAKE COVER NOW! Move to a basement or an interior room on the lowest floor of a sturdy building. Avoid windows. If you are outdoors, in a mobile home, or in a vehicle, move to the closest substantial shelter and protect yourself from flying debris.",
        area: "Fixture County; Example County",
        sender: "NWS Fixture City MO",
        onset_ms: -20 * 60000,
        ends_ms: 70 * 60000
    },
    thunder: {
        event: "Severe Thunderstorm Warning",
        severity: "Severe",
        urgency: "Immediate",
        headline: "Severe Thunderstorm Warning issued for Fixture County until 9:00 PM by NWS Fixture City",
        description: "A severe thunderstorm was located near the river crossing, moving east at 30 mph.\n\nHAZARD...60 mph wind gusts and quarter size hail.\n\nSOURCE...Radar indicated.\n\nIMPACT...Hail damage to vehicles is expected. Expect wind damage to roofs, siding, and trees.\n\nLocations impacted include Fixture City, Example Falls, Sample Heights and the airport.",
        instruction: "For your protection move to an interior room on the lowest floor of a building.",
        area: "Fixture County",
        sender: "NWS Fixture City MO",
        onset_ms: -45 * 60000,
        ends_ms: 3 * hour_ms
    },
    flood: {
        event: "Flood Advisory",
        severity: "Moderate",
        urgency: "Expected",
        headline: "Flood Advisory issued for Fixture County through tomorrow morning by NWS Fixture City",
        description: "* WHAT...Minor flooding caused by excessive rainfall is expected.\n\n* WHERE...Portions of the lowlands, including Fixture City, Example Falls and Sample Heights.\n\n* IMPACTS...Water over roadways. Low-lying and poor drainage areas may flood, and small streams will rise quickly.\n\n* ADDITIONAL DETAILS...Between 1 and 2 inches of rain have fallen, with additional rainfall of 1 to 2 inches expected over the next several hours.",
        instruction: "Turn around, don't drown when encountering flooded roads. Most flood deaths occur in vehicles.",
        area: "Fixture County; Example County; Sample County",
        sender: "NWS Fixture City MO",
        onset_ms: -2 * hour_ms,
        ends_ms: 14 * hour_ms
    }
};

function make_alert(now, key) {
    const a = alert_pool[key];
    return {
        event: a.event,
        severity: a.severity,
        urgency: a.urgency,
        headline: a.headline,
        description: a.description,
        instruction: a.instruction,
        onset: iso_in(now, a.onset_ms),
        ends: iso_in(now, a.ends_ms),
        area: a.area,
        sender: a.sender
    };
}

// Location-local hour of an hour entry is already in `hour`, so rain picks the afternoon by it.
function rain_patch(state) {
    const metric = state.data_unit === "celsius";
    const scale = metric ? 25.4 : 1;
    const first_date = state.hours.length > 0 ? state.hours[0].date : "";
    const hours = state.hours.map(h => {
        const afternoon = h.date === first_date && h.hour >= 13 && h.hour <= 20;
        const next_day = h.date !== first_date && h.hour >= 14 && h.hour <= 17;
        if (!afternoon && !next_day) return h;
        const peak = 1 - Math.abs(h.hour - 17) / 5;
        return Object.assign({}, h, {
            pop: Math.round(60 + 35 * Math.max(0, peak)),
            precip: Math.round(scale * (0.04 + 0.26 * Math.max(0, peak)) * 100) / 100,
            code: peak > 0.6 ? 65 : 63,
            cond: peak > 0.6 ? "Heavy rain" : "Moderate rain"
        });
    });
    const days = state.days.map((d, i) => {
        if (i !== 0 && i !== 1 && i !== 3) return d;
        return Object.assign({}, d, {
            pop: i === 0 ? 85 : 70,
            precip: Math.round(scale * (i === 0 ? 0.9 : 0.5) * 100) / 100,
            code: 63,
            cond: "Moderate rain"
        });
    });
    return { hours: hours, days: days };
}

function night_patch(state) {
    return {
        current: Object.assign({}, state.current, { is_day: 0, code: 0, cond: "Clear sky", uv_index: 0 }),
        hours: state.hours.map(h => Object.assign({}, h, { is_day: 0, code: 0, cond: "Clear sky", uv_index: 0 }))
    };
}

// `state` needs current, hours, days, data_unit; returns the fields the fixture overrides.
function patch(name, state, now) {
    switch (name) {
    case "base":
        return {};
    case "alerts1":
        return { alerts: [make_alert(now, "tornado")], alerts_has_data: true };
    case "alerts3":
        return { alerts: [make_alert(now, "tornado"), make_alert(now, "thunder"), make_alert(now, "flood")], alerts_has_data: true };
    case "aqi-bad": {
        const hours = state.hours.slice(0, 24);
        return {
            aq_current: { aqi: 228, pm25: 112.4, pm10: 160.8, ozone: 96 },
            aq_hours: hours.map((h, i) => ({ dt: h.dt, aqi: Math.round(150 + 90 * Math.sin(Math.min(1, i / 12) * Math.PI / 2) - Math.max(0, i - 14) * 6) })),
            aq_has_data: true
        };
    }
    case "rain":
        return rain_patch(state);
    case "night":
        return night_patch(state);
    }
    return null;
}

// Assigns the fixture onto `target` (WeatherState). With `synthetic`, the base state goes in first.
function apply(name, target, synthetic, now) {
    const stamp = now || Date.now();
    if (names.indexOf(name) < 0) return false;
    const fields = synthetic ? base(stamp) : {};
    if (synthetic) for (const key in fields) target[key] = fields[key];
    if (!target.has_data && !synthetic) return false;
    const changes = patch(name, target, stamp);
    for (const key in changes) target[key] = changes[key];
    if (synthetic) {
        target.moon = { phase: 0.5, name: "Full Moon" };
        target.has_data = true;
    }
    return true;
}
