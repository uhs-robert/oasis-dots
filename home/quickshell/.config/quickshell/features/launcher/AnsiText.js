.pragma library

// Turns terminal output with SGR colour codes (tmux capture-pane -e) into StyledText spans. Pane text is untrusted,
// so every character is escaped and only <font>, <b>, <i>, <u> and line breaks are emitted; every other escape sequence is dropped.
// StyledText has no dim, so dim paints the foreground at half strength. Colours are plain xterm hex: the styles have no ANSI palette tokens.

var base_colors = [
    "#000000", "#cd0000", "#00cd00", "#cdcd00", "#0000ee", "#cd00cd", "#00cdcd", "#e5e5e5",
    "#7f7f7f", "#ff0000", "#00ff00", "#ffff00", "#5c5cff", "#ff00ff", "#00ffff", "#ffffff"
];
var cube_levels = [0, 95, 135, 175, 215, 255];
var sequence_pattern = /\x1b(?:\[([0-9;:?<=>]*)([ -\/]*[@-~])|\][^\x07\x1b\n]*(?:\x07|\x1b\\)?|[ -\/]+[0-~]|[@-Z\\-_]|.)/g;

function hex2(n) {
    return (n < 16 ? "0" : "") + n.toString(16);
}

function rgb(r, g, b) {
    return "#" + hex2(r) + hex2(g) + hex2(b);
}

function clamp_byte(n) {
    return Math.max(0, Math.min(255, n | 0));
}

function palette_color(n) {
    if (n < 16) return base_colors[n];
    if (n < 232) {
        var i = n - 16;
        return rgb(cube_levels[Math.floor(i / 36)], cube_levels[Math.floor(i / 6) % 6], cube_levels[i % 6]);
    }
    var v = 8 + (n - 232) * 10;
    return rgb(v, v, v);
}

function escape(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function blank() {
    return { fg: "", bg: "", bold: false, dim: false, italic: false, underline: false, inverse: false };
}

// Reads the extended colour that starts at codes[i] (38 or 48); returns [color or "", next index].
function extended(codes, i) {
    if (codes[i + 1] === 5) return [codes[i + 2] === undefined ? "" : palette_color(clamp_byte(codes[i + 2])), i + 3];
    if (codes[i + 1] === 2) {
        if (codes.length < i + 5) return ["", codes.length];
        return [rgb(clamp_byte(codes[i + 2]), clamp_byte(codes[i + 3]), clamp_byte(codes[i + 4])), i + 5];
    }
    return ["", i + 1];
}

// "38:2:r:g:b" and "38:2::r:g:b" (empty colour-space slot) read like the ";" forms; other colon groups keep their
// first number (a styled underline "4:3" is just underline, "4:0" is off).
function sgr_codes(params) {
    if (params === "") return [0];
    var codes = [];
    params.split(";").forEach(function (group) {
        var parts = group.split(":").map(function (s) { return s === "" ? 0 : parseInt(s, 10); });
        if (parts.length === 1) codes.push(parts[0]);
        else if (parts[0] === 38 || parts[0] === 48) {
            if (parts[1] === 2 && parts.length >= 6) parts.splice(2, 1);
            codes = codes.concat(parts);
        } else codes.push(parts[0] === 4 && parts[1] === 0 ? 24 : parts[0]);
    });
    return codes;
}

function apply_sgr(state, params) {
    var codes = sgr_codes(params);
    for (var i = 0; i < codes.length; i++) {
        var c = codes[i];
        if (c === 0) Object.assign(state, blank());
        else if (c === 1) state.bold = true;
        else if (c === 2) state.dim = true;
        else if (c === 3) state.italic = true;
        else if (c === 4) state.underline = true;
        else if (c === 7) state.inverse = true;
        else if (c === 22) { state.bold = false; state.dim = false; }
        else if (c === 23) state.italic = false;
        else if (c === 24) state.underline = false;
        else if (c === 27) state.inverse = false;
        else if (c >= 30 && c <= 37) state.fg = base_colors[c - 30];
        else if (c >= 90 && c <= 97) state.fg = base_colors[c - 90 + 8];
        else if (c >= 40 && c <= 47) state.bg = base_colors[c - 40];
        else if (c >= 100 && c <= 107) state.bg = base_colors[c - 100 + 8];
        else if (c === 39) state.fg = "";
        else if (c === 49) state.bg = "";
        else if (c === 38 || c === 48) {
            var got = extended(codes, i);
            if (c === 38) state.fg = got[0]; else state.bg = got[0];
            i = got[1] - 1;
        }
    }
}

function mix_half(hex) {
    var v = parseInt(hex.slice(1), 16);
    return rgb(((v >> 16) & 255) >> 1, ((v >> 8) & 255) >> 1, (v & 255) >> 1);
}

// StyledText has no background colour, so background codes are dropped and inverse cannot swap: that would paint the
// text in the pane's own background and hide it. Inverse text (selected rows, highlighted prompts) is bold and underlined instead.
function wrap(text, state, default_fg) {
    var fg = state.fg;
    if (state.dim) fg = mix_half(fg || default_fg);
    // StyledText collapses runs of plain spaces, which would flatten a pane's indentation and box drawing.
    var out = escape(text).replace(/ /g, "&nbsp;");
    if (fg !== "") out = "<font color=\"" + fg + "\">" + out + "</font>";
    if (state.underline || state.inverse) out = "<u>" + out + "</u>";
    if (state.italic) out = "<i>" + out + "</i>";
    if (state.bold || state.inverse) out = "<b>" + out + "</b>";
    return out;
}

// default_fg is a "#rrggbb" string for text with no colour set (dim needs it).
function to_styled(input, default_fg) {
    var state = blank();
    var out = "";
    var last = 0;
    var m;
    sequence_pattern.lastIndex = 0;
    function flush(upto) {
        var chunk = input.slice(last, upto).replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "").replace(/\r/g, "");
        if (chunk === "") return;
        var lines = chunk.split("\n");
        for (var i = 0; i < lines.length; i++) {
            if (i > 0) out += "<br/>";
            if (lines[i] !== "") out += wrap(lines[i], state, default_fg);
        }
    }
    while ((m = sequence_pattern.exec(input)) !== null) {
        flush(m.index);
        last = m.index + m[0].length;
        if (m[2] === "m" && m[1] !== undefined) apply_sgr(state, m[1]);
    }
    flush(input.length);
    return out;
}

// The last `count` lines of `text`, trailing blank lines dropped first: a pane's prompt sits above the empty rows below it.
function bottom_lines(text, count) {
    var lines = text.replace(/\s+$/, "").split("\n");
    return lines.slice(Math.max(0, lines.length - count)).join("\n");
}
