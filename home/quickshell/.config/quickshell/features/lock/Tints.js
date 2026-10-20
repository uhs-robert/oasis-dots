.pragma library

// Saved names from before a rename, read as the tint they became. The greeter's synced settings can hold one until
// the next sync, so pair() resolves them too, not only Style's loaders.
const renamed = { amber: "orange" };

function current_name(name) {
    return renamed[name] || name;
}

// The lock tint `name` as [base, bright] from the Theme singleton `t`; unknown names use primary.
// "classic" asks each skin for its original palette; a skin without one draws it as primary.
function pair(t, name) {
    const families = {
        primary: [t.theme_primary_strong, t.theme_primary_strong],
        secondary: [t.theme_secondary_strong, t.theme_secondary],
        red: [t.red, t.bright_red],
        // Oasis's bright yellow is orange, so orange takes it and yellow's bright is yellow lightened.
        orange: [t.syntax_constant, t.bright_yellow],
        yellow: [t.yellow, Qt.tint(t.yellow, Qt.rgba(1, 1, 1, 0.4))],
        green: [t.green, t.bright_green],
        cyan: [t.cyan, t.bright_cyan],
        // Oasis's bright blue drifts towards cyan, so blue's bright is blue lightened.
        blue: [t.blue, Qt.tint(t.blue, Qt.rgba(1, 1, 1, 0.35))],
        purple: [t.magenta, t.bright_magenta],
        white: [t.fg_core, t.fg_strong]
    };
    families.classic = families.primary;
    return families[current_name(name)] || families.primary;
}
