// home/quickshell/.config/quickshell/settings/sections/MouseSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."
import "../Choices.js" as Choices

RowsSection {
    id: root

    // -1 to 1 in tenths, built from integers so each step compares equal to the saved value.
    readonly property var speeds: Array.from({ length: 21 }, (_, i) => (i - 10) / 10)
    readonly property var focus_modes: ({ 0: "Off, click to focus", 1: "On", 2: "Pointer only, click for keys", 3: "Detached" })

    function toggle(label, key) {
        return {
            label: label,
            values: () => [false, true],
            text: v => v ? "On" : "Off",
            value: () => HyprInput.value(key),
            set: v => HyprInput.set(key, v),
            pick: false
        };
    }

    rows: [{
        label: "Pointer speed",
        values: () => Choices.with_current(root.speeds, HyprInput.value("sensitivity")),
        text: v => (v > 0 ? "+" : "") + v.toFixed(1),
        value: () => HyprInput.value("sensitivity"),
        set: v => HyprInput.set("sensitivity", v),
        pick: false
    }, {
        label: "Focus follows mouse",
        values: () => [0, 1, 2, 3],
        text: v => root.focus_modes[v] || String(v),
        value: () => HyprInput.value("follow_mouse"),
        set: v => HyprInput.set("follow_mouse", v)
    }, root.toggle("Natural scrolling (touchpad)", "natural_scroll"), root.toggle("Tap to click", "tap_to_click"), root.toggle("Disable touchpad while typing", "disable_while_typing")]

    footer: Text {
        Layout.fillWidth: true
        text: "Applies at once and wins over the machine profile's input values. Saved to " + HyprInput.state_dir + "/input.json"
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
