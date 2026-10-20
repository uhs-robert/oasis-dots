.pragma library

// The lock tint `name` as [base, bright] from the Theme singleton `t`; unknown names use primary.
// "classic" asks each skin for its original palette; a skin without one draws it as primary.
function pair(t, name) {
    const families = {
        primary: [t.theme_primary_strong, t.theme_primary_strong],
        secondary: [t.theme_secondary_strong, t.theme_secondary],
        green: [t.green, t.bright_green],
        amber: [t.syntax_constant, t.bright_yellow],
        white: [t.fg_core, t.fg_strong]
    };
    families.classic = families.primary;
    return families[name] || families.primary;
}
