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

// The contentY that shows a row with the least scrolling. `lead` keeps a group heading with its first row above it;
// `foot` is the bottom fade's height, so the row ends above the fade instead of under it. At the very end the fade
// is gone, so the clamp to the content height needs no `foot`.
function reveal_target(row_top, row_height, content_y, view_height, content_height, lead, foot) {
    let target = content_y;
    if (row_top - lead < target) target = row_top - lead;
    else if (row_top + row_height > target + view_height - foot) target = row_top + row_height - view_height + foot;
    return Math.max(0, Math.min(target, content_height - view_height));
}
