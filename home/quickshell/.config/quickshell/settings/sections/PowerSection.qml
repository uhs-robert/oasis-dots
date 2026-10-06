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

    readonly property var idle_notes: ({
            dim: "Dim the screen after this long without input. Never disables it.",
            lock: "Lock the session after this long without input. Never disables it.",
            screen_off: "Turn the screen off after this long without input. Never disables it.",
            suspend: "Suspend the machine after this long without input. Never disables it."
        })

    function idle_row(name, source) {
        const key = name + "_" + source;
        return {
            label: root.idle_labels[name] + " on " + root.source_label(source),
            desc: root.idle_notes[name],
            values: () => PowerSettings.idle_choices(key),
            text: v => PowerSettings.duration_text(v),
            value: () => PowerSettings.values[key],
            set: v => PowerSettings.set(key, v)
        };
    }

    function choice_row(label, key, choices, desc) {
        return {
            label: label,
            desc: desc,
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
            rows.push(root.choice_row("Lid closed on AC", "lid_ac", PowerSettings.lid_actions, "What closing the lid does while on AC power."));
            rows.push(root.choice_row("Lid closed on battery", "lid_battery", PowerSettings.lid_actions, "What closing the lid does while on battery."));
        }
        rows.push(root.choice_row("Power button", "power_button", PowerSettings.button_actions, "What pressing the power button does."));
        for (const source of sources) rows.push(root.choice_row("Power profile on " + root.source_label(source), "profile_" + source, PowerSettings.profiles, "Power profile to switch to on " + root.source_label(source) + ". Leave as is changes nothing."));
        return rows;
    }

    rows: root.build_rows()
}
