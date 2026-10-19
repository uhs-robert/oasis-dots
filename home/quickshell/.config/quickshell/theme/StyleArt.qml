pragma Singleton
import QtQuick
import Quickshell
import "../styles/goldeneye/Watch.js" as Watch

// What shared widgets need from style art files, kept out of Style.qml because that file is staged for the greeter.
Singleton {
    // The token stays "<style>/File.qml" because the style tokens (styles/<style>/tokens.js) are staged for the greeter; the file lives under styles/<style>/widgets/.
    function widget_url(token) {
        return token === "" ? "" : Qt.resolvedUrl("../styles/" + token.replace("/", "/widgets/"));
    }

    // Warm run then blues, light end first, the order the gauge dial fills.
    function bezel_heat(fraction) {
        const k = Math.min(7, Math.floor((fraction < 0.5 ? fraction : fraction - 0.5) * 16));
        return fraction < 0.5 ? Watch.warm[7 - k] : Watch.cold_lit[7 - k];
    }
}
