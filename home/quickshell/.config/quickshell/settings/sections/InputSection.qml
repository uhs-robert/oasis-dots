// home/quickshell/.config/quickshell/settings/sections/InputSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."
import "../Choices.js" as Choices

RowsSection {
    id: root

    readonly property var modes: ({ insert: "INSERT", normal: "NORMAL" })
    readonly property var which_key_delays: [0, 100, 200, 300, 500, 750, 1000]

    rows: [{
        label: "Start typing in",
        desc: "Mode pickers, settings lists and search popups open in. NORMAL starts on the vim keys.",
        values: () => InputSettings.choices.start_mode,
        text: v => root.modes[v] || String(v),
        value: () => InputSettings.values.start_mode,
        set: v => InputSettings.set("start_mode", v)
    }, {
        label: "Remember last search",
        desc: "Refill each picker's query from its last open, until the shell restarts.",
        values: () => InputSettings.choices.remember_query,
        text: v => v ? "On" : "Off",
        value: () => InputSettings.values.remember_query,
        set: v => InputSettings.set("remember_query", v),
        pick: false
    }, {
        label: "Which-key delay",
        desc: "How long a leader key waits before its overlay shows. Reloads Hyprland to apply.",
        values: () => Choices.with_current(root.which_key_delays, HyprInput.value("which_key_delay_ms")),
        text: v => v === 0 ? "Instant" : v + " ms",
        value: () => HyprInput.value("which_key_delay_ms"),
        set: v => HyprInput.set("which_key_delay_ms", v)
    }]

    footer: Text {
        Layout.fillWidth: true
        text: "From NORMAL, i or / starts typing. The HyprVim prompt always opens in INSERT. Saved to " + InputSettings.state_dir + "/input.json and " + HyprInput.state_dir + "/input.json"
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
