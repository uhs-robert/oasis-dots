import QtQuick
import Quickshell
import Quickshell.Io
import qs.features.audio

// Caller-supplied choices from Prompt.select or a shell caller (`voxcmd ask pick`). The mode arg is a JSON spec path:
// { id, label, choices, result_path, expansions, view_path }. Enter or close writes the pick (empty on cancel) to
// result_path, then runs the Lua callback for that id once. A spec without an id is a shell caller blocking on
// result_path, so there is no callback to run.
// A choice may be { label, expand: key } naming one of expansions { key: { title, choices } }: Tab shows that list,
// whose picks are written as "<key><TAB><label>", and the shown key ("" at the top) is written to view_path.
// The voice key answers it whoever opened it (PickerVoice). An answer finishes the session as a click or Esc does.
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
    voice_answerable: true
    voice_question: root.session && !root.loading && Array.isArray(root.spec.choices) ? root.question_for_voice(root.view) : null

    // Specs are read asynchronously, and a spec's id and result_path exist only once it is read. An open that
    // lands while one is still loading is queued rather than started, so the load in flight can finish and answer
    // its caller; start_load takes the queue one arg at a time.
    property bool loading: false
    property var queued_args: []

    function refresh(arg) {
        if (root.loading) {
            root.session = true;
            root.queued_args = root.queued_args.concat([arg]);
            return;
        }
        // A second open while one shows would drop a Lua caller's callback, so answer it as Escape does. A shell
        // caller (no id) is left to its own timeout: its cleanup runs `picker close`, which would close this new picker.
        if (root.spec.id) root.finish("");
        root.session = true;
        root.start_load(arg);
    }

    function start_load(arg) {
        root.loading = true;
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

    function question_for_voice(view_key) {
        const expansions = {};
        for (const key in root.spec.expansions || {}) {
            const e = root.expansion(key);
            expansions[key] = { title: String(e.title || ""), choices: (e.choices || []).map(c => ({ id: String(c), label: String(c) })) };
        }
        const choices = root.top_items().map((item, i) => {
            const c = root.spec.choices[i];
            const choice = { id: c !== null && typeof c === "object" && c.id !== undefined ? String(c.id) : item.label, label: item.label };
            if (item.expand !== "") choice.expand = item.expand;
            return choice;
        });
        return { label: String(root.spec.label || ""), choices: choices, expansions: expansions, view_key: view_key };
    }

    function voice_answer(text) {
        const tab = text.indexOf("\t");
        const key = tab < 0 ? "" : text.slice(0, tab);
        const label = tab < 0 ? text : text.slice(tab + 1);
        const item = key === root.view ? root.items.find(i => i.label === label) : null;
        if (!root.session || !item) return false;
        // As Picker.activate does for a click: close first, so the close reads as a pick, not a cancel.
        ThemeAudio.play("confirm");
        Pickers.close();
        root.activate(item);
        return true;
    }

    function voice_expand(index) {
        const item = root.view === "" ? root.items[index - 1] : null;
        if (!root.session || !item || item.expand === "") return false;
        root.expand_requested(item);
        return true;
    }

    Process {
        id: spec_proc
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                let parsed = null;
                try {
                    parsed = JSON.parse(text);
                    // null parses fine but every later root.spec read would throw
                    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed))
                        throw new Error("not an object");
                } catch (e) {
                    console.warn("ChoicesProvider: invalid spec (" + e + ")");
                    parsed = null;
                }
                // Stale: a later open is queued behind it, or the picker was cancelled while it loaded. Only an id
                // caller is answered (as Escape does); a shell caller's own cleanup would close the newer picker.
                const stale = parsed !== null && (root.queued_args.length > 0 || !root.session);
                const was_live = root.session;
                if (stale && parsed.id) {
                    root.spec = parsed;
                    root.session = true;
                    root.finish("");
                }
                if (root.queued_args.length > 0) {
                    const next = root.queued_args[0];
                    root.queued_args = root.queued_args.slice(1);
                    // A cancelled session stays cancelled: queued callers are read only to be answered.
                    root.session = was_live;
                    root.start_load(next);
                    return;
                }
                if (!parsed || stale) return;
                root.spec = parsed;
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
