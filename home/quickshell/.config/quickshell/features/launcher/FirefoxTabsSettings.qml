pragma Singleton
import QtQuick
import Quickshell
import qs.core
import "../../core/Validated.js" as Validated
import "FirefoxTabs.js" as FirefoxTabs

// The Firefox tabs picker's last sort (`s`), saved in firefox_tabs.json under the Quickshell state dir so it outlives
// the picker and the bar.
Singleton {
    id: root

    readonly property var choices: ({ sort: FirefoxTabs.sorts })
    readonly property var defaults: ({ sort: FirefoxTabs.sorts[0] })

    readonly property string sort: store.values.sort

    function valid(key, value) {
        return Validated.in_choices(root.choices, key, value);
    }

    function set(key, value) {
        if (!root.valid(key, value)) return;
        store.set_key(key, value);
    }

    JsonStore {
        id: store
        path: Paths.state_dir + "/firefox_tabs.json"
        defaults: root.defaults
        debounce_ms: 300
        validate: raw => Validated.validated(root.defaults, raw, root.valid)
    }
}
