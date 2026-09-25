// home/quickshell/.config/quickshell/picker/PickerProvider.qml
import QtQuick
import Quickshell
import "../services"

// Base for a picker source. Items are { id, label, description, icon, keywords }; any other fields pass through.
Scope {
    id: root

    required property string name
    property string title: root.name
    property string placeholder: "Search"
    property var items: []
    // Grid columns when docked; an anchored picker is always a single column.
    property int columns: 1
    property bool rank_by_usage: true
    // Keep the items' own order when nothing is typed, and on equal scores.
    property bool keep_order: false
    property bool starts_insert: true
    // Opening it again while open steps to the next row, so a held Alt+Tab cycles.
    property bool repeat_steps: false
    // Selected row on open and whenever the query is cleared.
    property int initial_index: 0
    property string verb: "open"
    // Normal-mode keys run on the selected item: [{ key, desc }] handled by run_action.
    property var actions: []
    // Drawn beside the list with `entry` set to the selected item.
    property Component preview: null

    // Called on every open with the opener's mode arg, so keep it cheap; an item's `icon_path` skips the picker's icon lookup.
    function refresh(arg) {}

    function activate(item) {}

    function run_action(key, item) {}

    Component.onCompleted: Pickers.register(root)
}
