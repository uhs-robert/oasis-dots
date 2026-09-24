.pragma library

// fzf v1 scoring constants.
const score_match = 16;
const gap_start = -3;
const gap_extension = -1;
const bonus_boundary_white = 10;
const bonus_boundary = 9;
const bonus_camel = 7;
const bonus_consecutive = 4;
const first_char_multiplier = 2;

function char_class(c) {
    if (c === undefined) return "white";
    if (/\s/.test(c)) return "white";
    if (/[\/,:;|\-_.()\[\]]/.test(c)) return "delimiter";
    if (/[0-9]/.test(c)) return "number";
    if (c !== c.toLowerCase()) return "upper";
    if (c !== c.toUpperCase()) return "lower";
    return "other";
}

function bonus_at(text, i) {
    const prev = char_class(i > 0 ? text[i - 1] : undefined);
    const cur = char_class(text[i]);
    if (cur === "white" || cur === "delimiter") return 0;
    if (prev === "white") return bonus_boundary_white;
    if (prev === "delimiter") return bonus_boundary;
    if (prev === "lower" && cur === "upper") return bonus_camel;
    if (prev !== "number" && cur === "number") return bonus_camel;
    return 0;
}

// Scores one lowercase term against text; null when it does not match in order.
function match(term, text) {
    const n = term.length;
    if (n === 0) return { score: 0, positions: [] };
    const lower = text.toLowerCase();
    let pi = 0;
    let end = -1;
    for (let i = 0; i < lower.length; i++) {
        if (lower[i] === term[pi] && ++pi === n) {
            end = i;
            break;
        }
    }
    if (end < 0) return null;
    // Walk back from the end to the shortest window holding the term.
    let start = end;
    pi = n - 1;
    for (let i = end; i >= 0; i--) {
        if (lower[i] === term[pi] && --pi < 0) {
            start = i;
            break;
        }
    }
    const positions = [];
    let score = 0;
    let consecutive = 0;
    let first_bonus = 0;
    let in_gap = false;
    pi = 0;
    for (let i = start; i <= end; i++) {
        if (pi < n && lower[i] === term[pi]) {
            let bonus = bonus_at(text, i);
            if (consecutive === 0) {
                first_bonus = bonus;
            } else {
                if (bonus >= bonus_boundary && bonus > first_bonus) first_bonus = bonus;
                bonus = Math.max(bonus, first_bonus, bonus_consecutive);
            }
            score += score_match + (pi === 0 ? bonus * first_char_multiplier : bonus);
            positions.push(i);
            consecutive++;
            in_gap = false;
            pi++;
        } else {
            score += in_gap ? gap_extension : gap_start;
            consecutive = 0;
            in_gap = true;
        }
    }
    return { score: score, positions: positions };
}

function terms_of(query) {
    return query.toLowerCase().split(/\s+/).filter(t => t !== "");
}

// Every term must match the label, description or a keyword; only label matches are highlighted.
function score_item(terms, item) {
    let total = 0;
    let positions = [];
    const keywords = (item.keywords || []).join(" ");
    for (const term of terms) {
        const on_label = match(term, item.label || "");
        const on_desc = item.description ? match(term, item.description) : null;
        const on_keys = keywords !== "" ? match(term, keywords) : null;
        const best = Math.max(on_label ? on_label.score + 8 : -Infinity, on_desc ? on_desc.score * 0.6 : -Infinity, on_keys ? on_keys.score * 0.5 : -Infinity);
        if (best === -Infinity) return null;
        total += best;
        if (on_label && on_label.score + 8 === best) positions = positions.concat(on_label.positions);
    }
    return { score: total, positions: positions };
}

function escape_html(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// Rich text for Text.StyledText with the matched characters drawn in `color`.
function highlight(text, positions, color) {
    if (!positions || positions.length === 0) return escape_html(text);
    const hit = {};
    for (const p of positions) hit[p] = true;
    let out = "";
    let run = "";
    let run_hit = false;
    const flush = () => {
        if (run === "") return;
        out += run_hit ? "<font color=\"" + color + "\"><b>" + escape_html(run) + "</b></font>" : escape_html(run);
        run = "";
    };
    for (let i = 0; i < text.length; i++) {
        const h = !!hit[i];
        if (h !== run_hit) {
            flush();
            run_hit = h;
        }
        run += text[i];
    }
    flush();
    return out;
}
