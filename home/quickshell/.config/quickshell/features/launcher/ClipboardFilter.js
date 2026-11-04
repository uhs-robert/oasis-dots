.pragma library

// The clipboard picker's type filter (`f`), kept here so node can test it. Binary entries are neither text nor
// images, so only "all" keeps them.
var filters = ["all", "text", "image"];
var filter_labels = { all: "ALL", text: "TEXT", image: "IMAGES" };

function cycled_filter(filter) {
    var i = filters.indexOf(filter);
    return filters[(i + 1) % filters.length];
}

function kept_by_filter(kind, filter) {
    return filters.indexOf(filter) <= 0 || kind === filter;
}
