// home/quickshell/.config/quickshell/settings/sections/PowerSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    readonly property var idle_labels: ({ dim: "Dim", lock: "Lock", screen_off: "Screen off", suspend: "Suspend" })

    function source_label(source) {
        return source === "ac" ? "AC" : "battery";
    }

    function idle_row(name, source) {
        const key = name + "_" + source;
        return {
            label: root.idle_labels[name] + " on " + root.source_label(source),
            values: () => PowerSettings.idle_choices(key),
            text: v => PowerSettings.duration_text(v),
            value: () => PowerSettings.values[key],
            set: v => PowerSettings.set(key, v)
        };
    }

    function choice_row(label, key, choices) {
        return {
            label: label,
            values: () => choices,
            text: v => v === "keep" ? "Leave as is" : v,
            value: () => key.indexOf("profile_") === 0 ? PowerSettings.profile_of(key) : PowerSettings.values[key],
            set: v => PowerSettings.set(key, v)
        };
    }

    function build_rows() {
        const sources = PowerSettings.laptop ? ["ac", "battery"] : ["ac"];
        const rows = [];
        for (const name of ["dim", "lock", "screen_off", "suspend"]) {
            for (const source of sources) rows.push(root.idle_row(name, source));
        }
        if (PowerSettings.laptop) {
            rows.push(root.choice_row("Lid closed on AC", "lid_ac", PowerSettings.lid_actions));
            rows.push(root.choice_row("Lid closed on battery", "lid_battery", PowerSettings.lid_actions));
        }
        rows.push(root.choice_row("Power button", "power_button", PowerSettings.button_actions));
        for (const source of sources) rows.push(root.choice_row("Power profile on " + root.source_label(source), "profile_" + source, PowerSettings.profiles));
        return rows;
    }

    rows: root.build_rows()

    footer: Text {
        Layout.fillWidth: true
        text: "Idle times count from the last input. Saved to " + PowerSettings.state_dir + "/power.json"
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
