// home/quickshell/.config/quickshell/picker/ChoicesProvider.qml
import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

// Caller-supplied choices from Prompt.select or a shell caller (voxcmd-pick). The mode arg is a JSON spec path: { id, label, choices, result_path }.
// Enter or close writes the pick (empty on cancel) to result_path, then runs the Lua callback for that id once.
// A spec without an id is a shell caller blocking on result_path, so there is no callback to run.
PickerProvider {
    id: root

    name: "choices"
    title: root.spec.label || "Choose"
    placeholder: "Search"
    verb: "select"
    rank_by_usage: false
    keep_order: true

    property var spec: ({})
    // True from open until the callback is dispatched.
    property bool session: false

    function refresh(arg) {
        root.session = true;
        root.spec = {};
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
        root.finish(item.label);
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
                root.items = (root.spec.choices || []).map((c, i) => ({ id: i + ":" + c, label: c }));
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
