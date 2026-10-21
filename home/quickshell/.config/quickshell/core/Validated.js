.pragma library

// Defaults overlaid with each raw value the key's check accepts, so a hand-edited file can't leave a setting invalid.
function validated(defaults, raw, valid) {
    const next = Object.assign({}, defaults);
    for (const key in next) {
        if (valid(key, raw[key])) next[key] = raw[key];
    }
    return next;
}

function in_choices(choices, key, value) {
    return !!choices[key] && choices[key].indexOf(value) >= 0;
}
