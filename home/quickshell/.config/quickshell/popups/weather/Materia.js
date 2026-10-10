// home/quickshell/.config/quickshell/popups/weather/Materia.js
.pragma library

// WeatherState color keys folded into the style's materia kinds.
const kinds = {
    clear: "clear",
    partly_cloudy: "cloud",
    overcast: "cloud",
    fog: "fog",
    drizzle: "rain",
    rain: "rain",
    heavy_rain: "rain",
    freezing_rain: "rain",
    snow: "snow",
    heavy_snow: "snow",
    thunderstorm: "storm"
};

function kind(color_keys, code) {
    return kinds[color_keys[Math.round(code)]] || "cloud";
}

function color(materia, color_keys, code) {
    return materia[kind(color_keys, code)] || materia.cloud || "transparent";
}
