// home/quickshell/.config/quickshell/components/popup/fuzzy_rows.js
.pragma library
.import "../../picker/Fuzzy.js" as Fuzzy

function fuzzy_matches(rows, query) {
    const terms = Fuzzy.terms_of(query);
    if (terms.length === 0) return [];
    const found = [];
    for (let i = 0; i < rows.length; i++) if (Fuzzy.score_item(terms, { label: rows[i] })) found.push(i);
    return found;
}

// Highest-scoring row, or -1 when nothing matches.
function fuzzy_best(rows, query) {
    const terms = Fuzzy.terms_of(query);
    if (terms.length === 0) return -1;
    let best = -1;
    let best_score = -Infinity;
    for (let i = 0; i < rows.length; i++) {
        const m = Fuzzy.score_item(terms, { label: rows[i] });
        if (m && m.score > best_score) {
            best_score = m.score;
            best = i;
        }
    }
    return best;
}
