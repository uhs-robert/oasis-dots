.pragma library

// The mode a picker docked at the bottom opens in: its own choice in typing.json, else its group's.
// A provider names its group with PickerProvider.start_group; the keys are flat so Validated.js checks them like the rest.

var modes = ["insert", "normal"];
// Group -> its default mode. Browse pickers are mostly read, search pickers mostly typed into.
var group_defaults = { browse: "normal", search: "insert" };
var fallback_group = "search";
// Every picker that docks at the bottom, in the order Settings lists them under their group.
var bottom_pickers = ["clipboard", "agents", "apps", "dirs", "emoji", "keybinds", "choices"];

function group_key(group) {
    return group + "_start_mode";
}

function picker_key(name) {
    return name + "_start_mode";
}

function group_of(group) {
    return group_defaults.hasOwnProperty(group) ? group : fallback_group;
}

function choices() {
    const out = {};
    for (const group in group_defaults) out[group_key(group)] = modes;
    for (const name of bottom_pickers) out[picker_key(name)] = ["group"].concat(modes);
    return out;
}

function defaults() {
    const out = {};
    for (const group in group_defaults) out[group_key(group)] = group_defaults[group];
    for (const name of bottom_pickers) out[picker_key(name)] = "group";
    return out;
}

function group_mode(values, group) {
    const key = group_key(group_of(group));
    return modes.indexOf(values[key]) >= 0 ? values[key] : group_defaults[group_of(group)];
}

function docked_mode(values, name, group) {
    const own = values[picker_key(name)];
    return modes.indexOf(own) >= 0 ? own : group_mode(values, group);
}
