.pragma library

// A cue shows from this many px of hidden content, so a settled scroll at the very end does not flicker one.
const slack = 1;

// Which edges of a scrolled view hide content: { top, bottom }.
function hidden_edges(content_y, view_height, content_height) {
    return {
        top: content_y > slack,
        bottom: content_y + view_height < content_height - slack,
    };
}

// The contentY that shows a row with the least scrolling. `fade` is the fades' height, so the row sits clear of
// them instead of under them; `lead` keeps a group heading with its first row above it, and the larger of the two
// wins at the top. At either end the fade there is gone, so the clamps need no margin.
function reveal_target(row_top, row_height, content_y, view_height, content_height, lead, fade) {
    const head = Math.max(lead, fade);
    let target = content_y;
    if (row_top - head < target) target = row_top - head;
    else if (row_top + row_height > target + view_height - fade) target = row_top + row_height - view_height + fade;
    return Math.max(0, Math.min(target, content_height - view_height));
}
