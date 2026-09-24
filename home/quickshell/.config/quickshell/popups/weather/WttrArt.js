// home/quickshell/.config/quickshell/popups/weather/WttrArt.js
.pragma library

// wttr.in's condition drawings; a mask line colors its line per character, else the art's base key does.
const arts = {
    sun: { base: "y", lines: ["    \\   /    ", "     .-.     ", "  ─ (   ) ─  ", "     `-’     ", "    /   \\    "] },
    partly: {
        base: "c",
        lines: ["   \\  /      ", " _ /\"\".-.    ", "   \\_(   ).  ", "   /(___(__) ", "             "],
        masks: ["   y  y      ", " y yyyccc    ", "   yyc   cc  ", "   ycccccccc ", ""]
    },
    cloudy: { base: "c", lines: ["             ", "     .--.    ", "  .-(    ).  ", " (___.__)__) ", "             "] },
    overcast: { base: "d", lines: ["             ", "     .--.    ", "  .-(    ).  ", " (___.__)__) ", "             "] },
    fog: { base: "f", lines: ["             ", " _ - _ - _ - ", "  _ - _ - _  ", " _ - _ - _ - ", "             "] },
    light_rain: { base: "c", lines: ["     .-.     ", "    (   ).   ", "   (___(__)  ", "    ‘ ‘ ‘ ‘  ", "   ‘ ‘ ‘ ‘   "], masks: ["", "", "", "rrrrrrrrrrrrr", "rrrrrrrrrrrrr"] },
    heavy_rain: { base: "d", lines: ["     .-.     ", "    (   ).   ", "   (___(__)  ", "  ‚‘‚‘‚‘‚‘   ", "  ‚’‚’‚’‚’   "], masks: ["", "", "", "rrrrrrrrrrrrr", "rrrrrrrrrrrrr"] },
    sleet: { base: "c", lines: ["     .-.     ", "    (   ).   ", "   (___(__)  ", "    ‘ * ‘ *  ", "   * ‘ * ‘   "], masks: ["", "", "", "    r s r s  ", "   s r s r   "] },
    light_snow: { base: "c", lines: ["     .-.     ", "    (   ).   ", "   (___(__)  ", "    *  *  *  ", "   *  *  *   "], masks: ["", "", "", "sssssssssssss", "sssssssssssss"] },
    heavy_snow: { base: "d", lines: ["     .-.     ", "    (   ).   ", "   (___(__)  ", "   * * * *   ", "  * * * *    "], masks: ["", "", "", "sssssssssssss", "sssssssssssss"] },
    thunder: { base: "d", lines: ["     .-.     ", "    (   ).   ", "   (___(__)  ", "  ‚‘ _/ ‚‘   ", "  ‚’ /  ‚’   "], masks: ["", "", "", "  rr tt rr   ", "  rr t  rr   "] },
    unknown: { base: "u", lines: ["    .-.      ", "     __)     ", "    (        ", "     `-’     ", "      •      "] }
};

// Two-line cell icons for the day table.
const minis = {
    sun: { base: "y", lines: ["\\ | /", "-( )-"] },
    partly: { base: "c", lines: ["\\ .-.", "-(__)"], masks: ["y", "y"] },
    cloudy: { base: "c", lines: [" .-. ", "(___)"] },
    overcast: { base: "d", lines: [" .-. ", "(___)"] },
    fog: { base: "f", lines: ["_ - _", " - _ "] },
    light_rain: { base: "c", lines: ["(___)", "‘ ‘ ‘"], masks: ["", "rrrrr"] },
    heavy_rain: { base: "d", lines: ["(___)", "‚‘‚‘‚"], masks: ["", "rrrrr"] },
    sleet: { base: "c", lines: ["(___)", "‘ * ‘"], masks: ["", "r s r"] },
    light_snow: { base: "c", lines: ["(___)", "*  * "], masks: ["", "sssss"] },
    heavy_snow: { base: "d", lines: ["(___)", "* * *"], masks: ["", "sssss"] },
    thunder: { base: "d", lines: ["(___)", "‚_/‚‘"], masks: ["", "rttrr"] },
    unknown: { base: "u", lines: [" ?? ", "    "] }
};

function kind(code) {
    switch (Math.round(code)) {
    case 0: return "sun";
    case 1: case 2: return "partly";
    case 3: return "overcast";
    case 45: case 48: return "fog";
    case 51: case 53: case 61: case 80: return "light_rain";
    case 55: case 63: case 65: case 81: case 82: return "heavy_rain";
    case 56: case 57: case 66: case 67: return "sleet";
    case 71: case 77: case 85: return "light_snow";
    case 73: case 75: case 86: return "heavy_snow";
    case 95: case 96: case 99: return "thunder";
    default: return code < 0 ? "unknown" : "cloudy";
    }
}

function escape(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/ /g, "&nbsp;");
}

function span(text, color) {
    return color ? "<font color=\"" + color + "\">" + escape(text) + "</font>" : escape(text);
}

// One line of runs, [[text, color], ...], as StyledText.
function runs(list) {
    return list.map(r => span(r[0], r[1])).join("");
}

// The art's line i as runs of one color key each.
function line_runs(art, i, palette) {
    const line = art.lines[i] || "";
    const mask = art.masks ? art.masks[i] || "" : "";
    const out = [];
    for (let c = 0; c < line.length; c++) {
        const ch = line[c];
        const key = ch === " " ? "" : mask[c] && mask[c] !== " " ? mask[c] : art.base;
        const color = key ? String(palette[key]) : "";
        if (out.length > 0 && (out[out.length - 1][1] === color || ch === " ")) out[out.length - 1][0] += ch;
        else out.push([ch, color]);
    }
    return out;
}

function markup(art, palette) {
    return art.lines.map((_, i) => runs(line_runs(art, i, palette))).join("<br>");
}
