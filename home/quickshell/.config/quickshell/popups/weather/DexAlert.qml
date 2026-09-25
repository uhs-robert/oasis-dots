// home/quickshell/.config/quickshell/popups/weather/DexAlert.qml
import QtQuick
import "../../components"
import "../../theme"
import "../../services"

// The first weather alert as a red Pokémon text box: "Warning! A COASTAL FLOOD is approaching!"
TextBox {
    id: root

    signal clicked()

    readonly property var alert: WeatherState.alerts.length > 0 ? WeatherState.alerts[0] : null
    readonly property var parts: {
        const words = root.alert ? root.alert.event.trim().split(/\s+/) : [];
        const kinds = ["Warning", "Watch", "Advisory", "Statement", "Emergency", "Outlook"];
        const last = words.length > 1 && kinds.indexOf(words[words.length - 1]) >= 0 ? words.pop() : "Alert";
        return { kind: last, event: words.join(" ").toUpperCase().replace(/&/g, "&amp;").replace(/</g, "&lt;") };
    }
    readonly property string until: root.alert && root.alert.ends ? WeatherState.fmt_location_time(new Date(root.alert.ends)) : ""

    rich: true
    inner: Theme.theme_label
    outer: Theme.theme_label
    text: !root.alert ? "" : root.parts.kind + "! " + (/^[AEIOU]/.test(root.parts.event) ? "An " : "A ") + "<font color=\"" + Theme.theme_label + "\">" + root.parts.event + "</font> is approaching!"
        + (root.until !== "" ? " It lasts until " + root.until + "." : "")
        + (WeatherState.alerts.length > 1 ? " (+" + (WeatherState.alerts.length - 1) + " more)" : "")

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
