pragma Singleton
import QtQuick
import Quickshell
import qs.core
import "../../core/Validated.js" as Validated

// The on-screen display's saved choices, in osd.json under the Quickshell state dir.
Singleton {
    id: root

    // "opposite" is the edge opposite the bar; "left" and "right" pin it to a side for every monitor.
    readonly property var choices: ({ edge: ["opposite", "left", "right"] })
    readonly property var defaults: ({ edge: "opposite" })

    readonly property var values: store.values
    readonly property string edge: root.values.edge

    // The screen edge the OSD hangs from on a monitor whose bar sits on `bar_edge` ("top" or "bottom").
    function edge_for(bar_edge) {
        if (root.edge !== "opposite") return root.edge;
        return bar_edge === "bottom" ? "top" : "bottom";
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
        path: Paths.state_dir + "/osd.json"
        defaults: root.defaults
        debounce_ms: 300
        validate: raw => Validated.validated(root.defaults, raw, root.valid)
    }
}
