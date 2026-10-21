.pragma library

// Mirrors VALID in config/input, which ignores anything else, so the panel never shows a value Hyprland did not apply.
// Kept in step with it by the vectors in tests/input_settings/vectors.tsv.
function valid(key, v) {
    const integer_in = (min, max) => Number.isInteger(v) && v >= min && v <= max;
    switch (key) {
    case "kb_layout": return typeof v === "string" && /^[A-Za-z0-9_,-]+$/.test(v);
    case "kb_variant": return typeof v === "string" && /^[A-Za-z0-9_,-]*$/.test(v);
    case "natural_scroll":
    case "tap_to_click":
    case "disable_while_typing": return typeof v === "boolean";
    case "repeat_rate": return integer_in(1, 100);
    case "repeat_delay": return integer_in(100, 2000);
    case "sensitivity": return typeof v === "number" && v >= -1 && v <= 1;
    case "follow_mouse": return integer_in(0, 3);
    case "which_key_delay_ms": return integer_in(0, 5000);
    case "pointer_keys": return v === "hjkl" || v === "wasd" || v === "both";
    }
    return false;
}
