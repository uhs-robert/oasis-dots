pragma Singleton
import QtQuick
import Quickshell
import qs.core
import "../../core/Validated.js" as Validated
import "StartMode.js" as StartMode

// Input choices saved in typing.json under the Quickshell state dir.
Singleton {
    id: root

    readonly property string state_dir: Paths.state_dir

    readonly property var choices: Object.assign({ start_mode: ["insert", "normal"], remember_query: [false, true] }, StartMode.choices())
    readonly property var defaults: Object.assign({ start_mode: "insert", remember_query: false }, StartMode.defaults())
    readonly property var bottom_pickers: StartMode.bottom_pickers

    readonly property var values: store.values
    // Island pickers, settings lists and type-to-search popups open in INSERT when true; keybind-opened pickers follow
    // docked_starts_insert and the HyprVim prompt always opens in INSERT.
    readonly property bool starts_insert: root.values.start_mode === "insert"
    // Last query per picker or settings list, for this session only; recall gives "" unless remember_query is on.
    property var last_queries: ({})

    function remember(key, text) {
        root.last_queries[key] = text;
    }

    function recall(key) {
        return root.values.remember_query ? root.last_queries[key] || "" : "";
    }

    function group_key(group) {
        return StartMode.group_key(group);
    }

    function picker_key(name) {
        return StartMode.picker_key(name);
    }

    function group_mode(group) {
        return StartMode.group_mode(root.values, group);
    }

    function docked_starts_insert(provider) {
        return StartMode.docked_mode(root.values, provider ? provider.name : "", provider ? provider.start_group : "") === "insert";
    }

    function valid(key, value) {
        return Validated.in_choices(root.choices, key, value);
    }

    function set(key, value) {
        if (!root.valid(key, value)) return;
        store.set_key(key, value);
    }

    JsonStore {
        id: store
        path: root.state_dir + "/typing.json"
        defaults: root.defaults
        debounce_ms: 300
        validate: raw => Validated.validated(root.defaults, raw, root.valid)
    }
}
