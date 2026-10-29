.pragma library

// Where a weekly Claude limit is heading at its average pace since the week began. Reset times arrive as text in
// their own IANA zone; QML's JS has no zone database, so `date_spec` hands them to `date` and the epoch comes back.

const day_ms = 86400000;
const week_ms = 7 * day_ms;
// Right after a reset a few percent extrapolates wildly.
const min_elapsed_ms = 12 * 3600000;

const months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const day_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function is_weekly(label) {
    return /week/i.test(label || "");
}

function pad2(n) {
    return n < 10 ? "0" + n : "" + n;
}

// "Nov 2, 9am (Europe/London)" or "Nov 2 at 5:59am" into wall-clock parts, or null. The text has no year: the one
// that puts the date nearest `now_ms` wins, so a "Jan 2" read on Dec 30 is next year's.
function reset_parts(resets, now_ms) {
    const m = /^([A-Za-z]{3})[A-Za-z]*\.?\s+(\d{1,2}),?\s*(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s*(?:\(([^)]*)\))?\s*$/i.exec((resets || "").trim());
    if (!m) return null;
    const month = months.indexOf(m[1].toLowerCase());
    const day = parseInt(m[2]);
    const hour12 = parseInt(m[3]);
    const minute = m[4] ? parseInt(m[4]) : 0;
    if (month < 0 || day < 1 || day > 31 || hour12 < 1 || hour12 > 12 || minute > 59) return null;
    const zone = (m[6] || "").trim();
    // The zone ends up inside a quoted TZ="..." in date's input, so only zone-name characters get through.
    if (zone !== "" && !/^[A-Za-z0-9_+-]+(\/[A-Za-z0-9_+-]+)*$/.test(zone)) return null;
    const now = new Date(now_ms);
    let year = now.getFullYear();
    let best = Infinity;
    for (const y of [year - 1, year, year + 1]) {
        const off = Math.abs(new Date(y, month, day).getTime() - now_ms);
        if (off < best) {
            best = off;
            year = y;
        }
    }
    return { year: year, month: month + 1, day: day, hour: hour12 % 12 + (/pm/i.test(m[5]) ? 12 : 0), minute: minute, zone: zone };
}

// The parts as "<zone>|YYYY-MM-DD HH:MM" for `date_script`; an empty zone means local time.
function date_spec(parts) {
    if (!parts) return "";
    return parts.zone + "|" + parts.year + "-" + pad2(parts.month) + "-" + pad2(parts.day) + " " + pad2(parts.hour) + ":" + pad2(parts.minute);
}

// `sh -c date_script sh <spec>...` prints an epoch, or "-", per spec. GNU date reads TZ="..." inside -d, but an
// unknown zone there silently means UTC, hence the zoneinfo test first.
const date_script = 'for spec; do zone=${spec%%|*}; when=${spec#*|}; ' +
    'if [ -z "$zone" ]; then date -d "$when" +%s 2>/dev/null || echo -; ' +
    'elif [ -f "${TZDIR:-/usr/share/zoneinfo}/$zone" ]; then date -d "TZ=\\"$zone\\" $when" +%s 2>/dev/null || echo -; ' +
    'else echo -; fi; done';

// Null when there is nothing worth saying; otherwise whether the limit is hit before the reset, when, and the
// percent the week ends on at this pace.
function project(percent, reset_ms, now_ms) {
    if (!(percent > 0) || !isFinite(reset_ms) || now_ms >= reset_ms) return null;
    const start_ms = reset_ms - week_ms;
    const elapsed_ms = now_ms - start_ms;
    if (elapsed_ms < min_elapsed_ms) return null;
    const full_ms = start_ms + elapsed_ms * 100 / percent;
    return { over: full_ms < reset_ms, full_ms: full_ms, end_percent: Math.round(percent * week_ms / elapsed_ms) };
}

// "Fri 3pm" in local time, to the nearest hour; `hour_label` turns 0-23 into the clock's hour text.
function when_label(ms, hour_label) {
    // Rounded on the local clock, not the epoch, so a half-hour zone still lands on the hour.
    const d = new Date(ms + 30 * 60000);
    d.setMinutes(0, 0, 0);
    return day_names[d.getDay()] + " " + hour_label(d.getHours());
}

// The line under a weekly bar: { shown, over, text, short, when, end_percent }. `when` is the hit time over pace, else
// the reset; `short` ("full by Fri 3pm", "~44% by Mon 9am") is for tight layouts and the bar tooltip.
function describe(label, percent, reset_ms, now_ms, hour_label) {
    const p = is_weekly(label) ? project(percent, reset_ms, now_ms) : null;
    if (!p) return { shown: false, over: false, text: "", short: "", when: "", end_percent: 0 };
    const when = when_label(p.over ? p.full_ms : reset_ms, hour_label);
    return {
        shown: true,
        over: p.over,
        text: p.over ? "At this rate you'll hit the limit by " + when : "On pace for ~" + p.end_percent + "% by " + when,
        short: p.over ? "full by " + when : "~" + p.end_percent + "% by " + when,
        when: when,
        end_percent: p.end_percent
    };
}
