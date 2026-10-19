import QtQuick
import Quickshell
import Quickshell.Io

// Caller-supplied choices from Prompt.select or a shell caller (voxcmd-pick). The mode arg is a JSON spec path:
// { id, label, choices, result_path, expansions, view_path }. Enter or close writes the pick (empty on cancel) to
// result_path, then runs the Lua callback for that id once. A spec without an id is a shell caller blocking on
// result_path, so there is no callback to run.
// A choice may be { label, expand: key } naming one of expansions { key: { title, choices } }: Tab shows that list,
// whose picks are written as "<key><TAB><label>", and the shown key ("" at the top) is written to view_path.
PickerProvider {
    id: root

    name: "choices"
    title: root.view !== "" ? root.expansion(root.view).title || root.view : root.spec.label || "Choose"
    placeholder: "Search"
    verb: "select"
    rank_by_usage: false
    keep_order: true

    property var spec: ({})
    // The expansion key shown, "" for the top-level choices.
    property string view: ""
    expands: root.view === "" && root.items.some(i => i.expand !== "")
    can_go_back: root.view !== ""
    // True from open until the callback is dispatched.
    property bool session: false

    function refresh(arg) {
        // A second open while one shows would otherwise drop the first caller; answer it as Escape does.
        root.finish("");
        root.session = true;
        root.spec = {};
        root.view = "";
        root.items = [];
        spec_proc.running = false;
        spec_proc.command = ["cat", arg];
        spec_proc.running = true;
    }

    function finish(text) {
        if (!root.session) return;
        root.session = false;
        if (!root.spec.id && !root.spec.result_path) return;
        Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" > \"$2\"; [ -z \"$3\" ] || hyprctl eval \"_hv_prompt_cb('$3')\"", "sh", text, root.spec.result_path || "/dev/null", root.spec.id || ""]);
    }

    function activate(item) {
        root.finish(root.view !== "" ? root.view + "\t" + item.label : item.label);
    }

    function expansion(key) {
        return (root.spec.expansions || {})[key] || { title: "", choices: [] };
    }

    function top_items() {
        return (root.spec.choices || []).map((c, i) => {
            const label = typeof c === "string" ? c : String(c.label);
            const key = typeof c === "string" ? "" : String(c.expand || "");
            const expansion = key !== "" ? root.expansion(key) : null;
            const tab_hint = expansion && expansion.choices.length > 0 ? "Tab: " + (expansion.title || key) + " (" + expansion.choices.length + ")" : "";
            return { id: i + ":" + label, label: label, expand: tab_hint !== "" ? key : "", description: tab_hint };
        });
    }

    function show(key) {
        root.view = key;
        root.items = key === "" ? root.top_items() : root.expansion(key).choices.map((c, i) => ({ id: key + "/" + i + ":" + c, label: c, expand: "" }));
        if (root.spec.view_path) Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" > \"$2\"", "sh", key, root.spec.view_path]);
    }

    function expand(item) {
        if (root.view !== "" || !item.expand) return false;
        root.show(item.expand);
        return true;
    }

    function go_back() {
        if (root.view !== "") root.show("");
    }

    Process {
        id: spec_proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.spec = JSON.parse(text);
                } catch (e) {
                    console.warn("ChoicesProvider: invalid spec (" + e + ")");
                    return;
                }
                root.items = root.top_items();
            }
        }
    }

    // Picker.activate closes before it activates, so a cancel is only a close nothing picked from.
    Timer {
        id: cancel_timer
        interval: 50
        onTriggered: if (root.session && (!Pickers.is_open || Pickers.provider_name !== root.name)) root.finish("")
    }

    Connections {
        target: Pickers
        function onIs_openChanged() {
            if (!Pickers.is_open) cancel_timer.restart();
        }
        function onProvider_nameChanged() {
            cancel_timer.restart();
        }
    }
}
