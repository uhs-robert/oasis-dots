import QtQuick
import QtQuick.Layouts
import qs.features.settings
import qs.features.launcher
import "Choices.js" as Choices

RowsSection {
    id: root

    readonly property var modes: ({ insert: "INSERT", normal: "NORMAL" })
    readonly property var which_key_delays: [0, 100, 200, 300, 500, 750, 1000]
    readonly property var groups: [{ id: "browse", label: "Browse pickers" }, { id: "search", label: "Search pickers" }]
    readonly property var picker_labels: ({ clipboard: "Clipboard", agents: "Agents", apps: "Apps", dirs: "Directories", emoji: "Emoji", keybinds: "Keybinds", choices: "Choices" })
    readonly property var picker_notes: ({ clipboard: " Its delete mode always opens in NORMAL, ready for d." })

    function group_of(name) {
        const provider = Pickers.providers[name];
        return provider ? provider.start_group : "search";
    }

    function members(group) {
        return TypingSettings.bottom_pickers.filter(name => root.group_of(name) === group);
    }

    function listed(labels) {
        return labels.length < 2 ? labels.join("") : labels.slice(0, -1).join(", ") + " and " + labels[labels.length - 1];
    }

    function group_rows(group) {
        const key = TypingSettings.group_key(group.id);
        const names = root.members(group.id);
        const head = {
            label: group.label,
            desc: "Mode " + root.listed(names.map(n => root.picker_labels[n] || n)) + " open in when docked at the bottom. Each can override it below.",
            values: () => TypingSettings.choices[key],
            text: v => root.modes[v] || String(v),
            value: () => TypingSettings.values[key],
            set: v => TypingSettings.set(key, v)
        };
        return [head].concat(names.map(name => {
            const own_key = TypingSettings.picker_key(name);
            const label = root.picker_labels[name] || name;
            return {
                label: label,
                indent: 1,
                desc: "Mode the " + label + " picker opens in at the bottom. Group follows " + group.label + "." + (root.picker_notes[name] || ""),
                values: () => TypingSettings.choices[own_key],
                text: v => v === "group" ? "Group (" + root.modes[TypingSettings.group_mode(group.id)] + ")" : root.modes[v] || String(v),
                value: () => TypingSettings.values[own_key],
                set: v => TypingSettings.set(own_key, v)
            };
        }));
    }

    rows: [{
        label: "Start typing in",
        desc: "Mode island pickers, settings lists and search popups open in. From NORMAL, i or / types; the HyprVim prompt is always INSERT.",
        values: () => TypingSettings.choices.start_mode,
        text: v => root.modes[v] || String(v),
        value: () => TypingSettings.values.start_mode,
        set: v => TypingSettings.set("start_mode", v)
    }].concat(...root.groups.map(g => root.group_rows(g))).concat([{
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
    }])
}
