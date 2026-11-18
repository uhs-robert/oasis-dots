pragma Singleton
import QtQuick
import Quickshell
import qs.core
import "../../core/Validated.js" as Validated

// The mail module's saved choices, in mail.json under the Quickshell state dir.
Singleton {
    id: root

    readonly property var choices: ({ interval_s: [60, 120, 300, 600] })
    readonly property var bools: ["skip_trash", "skip_junk", "mail_preview"]
    readonly property var defaults: ({ interval_s: 60, skip_trash: true, skip_junk: true, mail_preview: false })

    readonly property var values: store.values
    // Every poll makes Thunderbird read each folder's counts, so the shortest interval is a minute.
    readonly property int interval_s: root.values.interval_s
    readonly property bool skip_trash: root.values.skip_trash
    readonly property bool skip_junk: root.values.skip_junk
    // Off by default: sender and subject on screen are readable over a shoulder.
    readonly property bool mail_preview: root.values.mail_preview

    function valid(key, value) {
        if (key in root.choices) return Validated.in_choices(root.choices, key, value);
        return root.bools.indexOf(key) >= 0 && typeof value === "boolean";
    }

    function set(key, value) {
        if (!root.valid(key, value)) return;
        store.set_key(key, value);
    }

    JsonStore {
        id: store
        path: Paths.state_dir + "/mail.json"
        defaults: root.defaults
        debounce_ms: 300
        validate: raw => Validated.validated(root.defaults, raw, root.valid)
    }
}
