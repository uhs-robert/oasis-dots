.pragma library

// The bar clock's meeting markers: token -> label, in Settings order. MeetingMarker.qml maps each token to its file; "" is the dot.
var labels = {
    "": "Dot",
    "bracket_tag": "Bracket tag",
    "vt100_led": "VT100 LED",
    "mode_badge": "Mode badge",
    "bracket_readout": "Bracket readout",
    "hev_readout": "HEV readout",
    "lit_pill": "Lit pill",
    "pill_badge": "Pill badge",
    "encounter_sprite": "Encounter sprite",
    "reserve_box": "Reserve box",
    "pixel_calendar": "Pixel calendar",
    "memory_card": "Memory card",
    "atb_gauge": "ATB gauge",
    "energy_tanks": "Energy tanks",
    "ring_gauge": "Ring gauge",
    "lcd_subdial": "LCD subdial",
    "twinkle_star": "Twinkle star"
};

var tokens = Object.keys(labels);
