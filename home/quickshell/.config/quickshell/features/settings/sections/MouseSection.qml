import QtQuick
import QtQuick.Layouts
import qs.features.settings
import "../Choices.js" as Choices

RowsSection {
    id: root

    // -1 to 1 in tenths, built from integers so each step compares equal to the saved value.
    readonly property var speeds: Array.from({ length: 21 }, (_, i) => (i - 10) / 10)
    readonly property var focus_modes: ({ 0: "Off, click to focus", 1: "On", 2: "Pointer only, click for keys", 3: "Detached" })
    readonly property var pointer_key_names: ({ hjkl: "HJKL", wasd: "WASD", both: "Both" })

    function toggle(label, key, desc) {
        return {
            label: label,
            desc: desc,
            values: () => [false, true],
            text: v => v ? "On" : "Off",
            value: () => HyprInputSettings.value(key),
            set: v => HyprInputSettings.set(key, v),
            pick: false
        };
    }

    rows: [{
        label: "Pointer speed",
        desc: "Pointer acceleration, -1 (slowest) to +1 (fastest). Beats the machine profile.",
        values: () => Choices.with_current(root.speeds, HyprInputSettings.value("sensitivity")),
        text: v => (v > 0 ? "+" : "") + v.toFixed(1),
        value: () => HyprInputSettings.value("sensitivity"),
        set: v => HyprInputSettings.set("sensitivity", v),
        pick: false
    }, {
        label: "Focus follows mouse",
        desc: "Whether focus moves to the window under the pointer, or needs a click.",
        values: () => [0, 1, 2, 3],
        text: v => root.focus_modes[v] || String(v),
        value: () => HyprInputSettings.value("follow_mouse"),
        set: v => HyprInputSettings.set("follow_mouse", v)
    }, {
        label: "Pointer keys",
        desc: "Keys that move the keyboard pointer (Cursor mode). Reloads Hyprland to apply.",
        values: () => ["hjkl", "wasd", "both"],
        text: v => root.pointer_key_names[v] || String(v),
        value: () => HyprInputSettings.value("pointer_keys"),
        set: v => HyprInputSettings.set("pointer_keys", v)
    }, root.toggle("Natural scrolling (touchpad)", "natural_scroll", "Content follows your fingers on the touchpad, as on a phone."), root.toggle("Tap to click", "tap_to_click", "A tap on the touchpad clicks, without pressing it down."), root.toggle("Disable touchpad while typing", "disable_while_typing", "Ignore the touchpad while keys are being typed, so a palm does not move the pointer.")]
}
