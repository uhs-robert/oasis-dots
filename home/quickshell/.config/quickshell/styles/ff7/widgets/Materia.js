.pragma library

const names = ["green", "blue", "purple", "red", "yellow"];
const known = {
    kitty: "green",
    foot: "green",
    alacritty: "green",
    ghostty: "green",
    wezterm: "green",
    firefox: "blue",
    chromium: "blue",
    zen: "blue",
    "brave-browser": "blue"
};

function base(cls) {
    const key = String(cls || "").toLowerCase().split(".").pop();
    if (known[key]) return known[key];
    let h = 0;
    for (let i = 0; i < key.length; i++) h = (h * 31 + key.charCodeAt(i)) >>> 0;
    return names[h % names.length];
}

// Materia names for slots linked 0-1, 2-3; blue is kept only when linked to green or purple.
function slot_names(classes) {
    const out = classes.map(base);
    for (let i = 0; i < out.length; i++) {
        if (out[i] !== "blue") continue;
        const mate = i ^ 1;
        const partner = mate < out.length ? out[mate] : "";
        if (partner === "green" || partner === "purple") continue;
        out[i] = "green";
    }
    return out;
}
