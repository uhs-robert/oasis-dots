.pragma library

function hex2(n) {
    return (n < 16 ? "0" : "") + n.toString(16);
}

function rgb_hex(r, g, b) {
    return "#" + hex2(r) + hex2(g) + hex2(b);
}

function indexed(n, palette) {
    if (n < 16) return palette[n];
    if (n >= 232) {
        const v = 8 + (n - 232) * 10;
        return rgb_hex(v, v, v);
    }
    const c = n - 16;
    const level = v => (v === 0 ? 0 : 55 + v * 40);
    return rgb_hex(level(Math.floor(c / 36)), level(Math.floor(c / 6) % 6), level(c % 6));
}

function escape_html(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function blank_state() {
    return { fg: "", bg: "", bold: false, italic: false, underline: false, reverse: false };
}

// Applies one SGR parameter list to state; extended colors consume their arguments.
function apply_sgr(state, params, palette) {
    const p = params.length === 0 ? [0] : params;
    for (let i = 0; i < p.length; i++) {
        const n = p[i];
        if (n === 0) Object.assign(state, blank_state());
        else if (n === 1) state.bold = true;
        else if (n === 3) state.italic = true;
        else if (n === 4) state.underline = true;
        else if (n === 7) state.reverse = true;
        else if (n === 22) state.bold = false;
        else if (n === 23) state.italic = false;
        else if (n === 24) state.underline = false;
        else if (n === 27) state.reverse = false;
        else if (n >= 30 && n <= 37) state.fg = palette[n - 30];
        else if (n >= 90 && n <= 97) state.fg = palette[n - 90 + 8];
        else if (n >= 40 && n <= 47) state.bg = palette[n - 40];
        else if (n >= 100 && n <= 107) state.bg = palette[n - 100 + 8];
        else if (n === 39) state.fg = "";
        else if (n === 49) state.bg = "";
        else if (n === 38 || n === 48) {
            let color = "";
            if (p[i + 1] === 5 && p[i + 2] !== undefined) {
                color = indexed(p[i + 2] & 255, palette);
                i += 2;
            } else if (p[i + 1] === 2 && p[i + 4] !== undefined) {
                color = rgb_hex(p[i + 2] & 255, p[i + 3] & 255, p[i + 4] & 255);
                i += 4;
            } else {
                i = p.length;
            }
            if (n === 38) state.fg = color;
            else state.bg = color;
        }
    }
}

function span_open(state, default_fg, default_bg) {
    const fg = state.fg || default_fg;
    const bg = state.bg || default_bg;
    const shown_fg = state.reverse ? bg : fg;
    const shown_bg = state.reverse ? fg : bg;
    const css = [];
    if (shown_fg !== default_fg) css.push("color:" + shown_fg);
    if (shown_bg !== default_bg) css.push("background-color:" + shown_bg);
    if (state.bold) css.push("font-weight:bold");
    if (state.italic) css.push("font-style:italic");
    if (state.underline) css.push("text-decoration:underline");
    return css.length === 0 ? "" : "<span style=\"" + css.join(";") + "\">";
}

// `capture-pane -ep` output as rich text; palette holds the 16 base colors as hex strings.
function to_html(raw, palette, default_fg, default_bg, max_lines) {
    const lines = raw.replace(/\r/g, "").split("\n");
    while (lines.length > 0 && lines[lines.length - 1].replace(/\x1b\[[0-9;:]*[A-Za-z]/g, "").trim() === "") lines.pop();
    const kept = max_lines > 0 ? lines.slice(0, max_lines) : lines;
    const state = blank_state();
    const out = [];
    for (const line of kept) {
        let html = "";
        let open = span_open(state, default_fg, default_bg);
        let text = "";
        const flush = () => {
            if (text === "") return;
            html += open + escape_html(text) + (open === "" ? "" : "</span>");
            text = "";
        };
        const re = /\x1b\[([0-9;:]*)([A-Za-z])|\x1b[^\[]?/g;
        let last = 0;
        let m;
        while ((m = re.exec(line)) !== null) {
            text += line.slice(last, m.index);
            last = re.lastIndex;
            if (m[2] !== "m") continue;
            flush();
            apply_sgr(state, m[1] === "" ? [] : m[1].split(/[;:]/).map(s => parseInt(s, 10) || 0), palette);
            open = span_open(state, default_fg, default_bg);
        }
        text += line.slice(last);
        flush();
        out.push(html);
    }
    return out.join("<br>");
}
