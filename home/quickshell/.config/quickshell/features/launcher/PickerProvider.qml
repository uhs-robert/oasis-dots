import QtQuick
import Quickshell

// Base for a picker source. Items are { id, label, description, icon, keywords, glyph, accent }; any other fields pass through.
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
    // Which Settings > Input group sets its mode when opened from a keybind or IPC: "browse" (opens NORMAL by default) or "search".
    property string start_group: "search"
    // Most rows shown; 0 shows every match.
    property int max_results: 0
    // Opening it again while open steps to the next row, so a held Alt+Tab cycles.
    property bool repeat_steps: false
    // Selected row on open and whenever the query is cleared.
    property int initial_index: 0
    property string verb: "open"
    // Shown in place of the list when there are no items.
    property string empty_text: "Nothing to pick"
    // Normal-mode keys run on the selected item: [{ key, desc }] handled by run_action. `needs_item: false` runs it with no row selected (item is null).
    property var actions: []
    // Drawn beside the list (above the cards in the browse layout) with `entry` set to the selected item.
    property Component preview: null
    // Browse only: plain Tab or Shift+Tab swaps `preview` for this and back; it gets no `entry`. Null leaves Tab unused.
    property Component alt_preview: null
    // What the footer and help call alt_preview ("Tab usage").
    property string alt_preview_name: ""
    // "list" docks at the bottom from IPC, or drops from the island it was opened on. "browse" always drops from the
    // focused monitor's center island at about Settings' size: search, a preview whose size `=`/`-`/`p` change, then cards.
    property string layout: "list"
    // Preview size each browse open starts at: "off", "s", "m" or "l" (BrowseLayout.js).
    property string default_preview_size: "m"
    // One browse card, given `entry` (the item), `positions` (its query match) and `selected`; null draws the generic card.
    property Component card: null
    // Card size in unscaled pixels; the picker fits as many columns as the width allows.
    property size card_size: Qt.size(280, 112)
    // One line of the browse list view (`v`), given what `card` gets; null draws the generic row.
    property Component row: null
    // Shown in the search bar's corner beside the mode, e.g. the clipboard's type filter; "" shows nothing.
    property string status_text: ""
    // Draws status_text in the accent colour, for a state that narrows what the list shows.
    property bool status_active: false
    // Font for item glyphs; empty uses the style font.
    property string glyph_font: ""
    // Tab labels drawn above the query; the picker calls select_tab(i) on a switch, which must set `tab`.
    property var tabs: []
    property int tab: 0
    // Tab completes like HyprVim's command line: on an item, expand(item) may swap in a list under it, and while
    // can_go_back Backspace on an empty search calls go_back(). Tab steps rows unless `expands` or the layout is browse.
    property bool expands: false
    property bool can_go_back: false

    // Called on every open with the opener's mode arg, so keep it cheap; an item's `icon_path` skips the picker's icon lookup.
    function refresh(arg) {}

    function select_tab(i) {}

    function activate(item) {}

    function run_action(key, item) {}

    // Returns whether it swapped in a new list.
    function expand(item) {
        return false;
    }

    function go_back() {}

    Component.onCompleted: Pickers.register(root)
}
