import QtQuick
import QtQuick.Layouts
import qs.features.settings
import qs.features.launcher
import "Choices.js" as Choices

RowsSection {
    id: root

    readonly property var modes: ({ insert: "INSERT", normal: "NORMAL" })
    readonly property var which_key_delays: [0, 100, 200, 300, 500, 750, 1000]

    rows: [{
        label: "Start typing in",
        desc: "Mode island pickers and search popups open in. From NORMAL, i or / types; bottom pickers and the HyprVim prompt are always INSERT.",
        values: () => TypingSettings.choices.start_mode,
        text: v => root.modes[v] || String(v),
        value: () => TypingSettings.values.start_mode,
        set: v => TypingSettings.set("start_mode", v)
    }, {
        label: "Remember last search",
        desc: "Refill each picker's query from its last open, until the shell restarts.",
        values: () => TypingSettings.choices.remember_query,
        text: v => v ? "On" : "Off",
        value: () => TypingSettings.values.remember_query,
        set: v => TypingSettings.set("remember_query", v),
        pick: false
    }, {
        label: "Which-key delay",
        desc: "How long a leader key waits before its overlay shows. Reloads Hyprland to apply.",
        values: () => Choices.with_current(root.which_key_delays, HyprInputSettings.value("which_key_delay_ms")),
        text: v => v === 0 ? "Instant" : v + " ms",
        value: () => HyprInputSettings.value("which_key_delay_ms"),
        set: v => HyprInputSettings.set("which_key_delay_ms", v)
    }]
}
