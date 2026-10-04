// home/quickshell/.config/quickshell/overview/OverviewBase.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../components"
import "../theme"
import "../services"
import "Layout.js" as Layout
import "../picker/Fuzzy.js" as Fuzzy

// The shared full-screen overview shell: grouped tiles, keys, search and help; the derived file fills in the data.
PanelWindow {
    id: root

    property bool wanted: false
    property string held_screen_name: ""
    // The filmstrip view instead of the mini-map, until the overview closes.
    property bool filmstrip: false
    property real reveal: 0

    property string selected_key: ""
    // Carried items, and the marks they came from so Esc can put them back.
    property var picked: []
    property bool picked_from_marks: false
    property var marks: []
    property bool typing: false
    property bool help_open: false
    property string query: ""
    property int hit: 0
    property bool from_search: false

    property var groups: []
    property var tiles: []
    property var ranked: []

    property string layer_namespace: ""
    property string title: ""
    property string status_text: ""
    property bool status_accent: root.carrying || root.marks.length > 0 || root.query !== ""
    property string footer_text: ""
    property string help_text: ""
    property string help_close_desc: "close overview"
    property string cursor_sub: ""
    property bool zero_digit_jumps: false

    property var group_label: (g, i) => ""
    // "done" accepts the key, "stop" leaves it unaccepted, "" goes on to the shared keys.
    property var pre_key: event => ""
    property var extra_key: (event, before) => false
    property var dismiss: () => {}
    property var activate: () => {}
    property var drop: () => {}
    property var pick: () => {}
    property var cancel_pick: () => {}
    property var toggle_mark: () => {}
    property var toggle_mark_all: () => {}
    property var close_selected: () => {}
    property var select: (index, sub) => {}
    property var select_entry: entry => {}
    property var reset_hit: () => {}
    property var accept_hit: () => {}
    property var jump: n => false
    property var filmstrip_vertical: dy => {}

    readonly property Item body: frame.body
    readonly property ListModel tile_slots: ListModel {}

    readonly property var tile_index_of: {
        const out = {};
        root.tiles.forEach((t, i) => out[t.key] = i);
        return out;
    }
    readonly property int selected_index: Math.max(0, root.tiles.findIndex(t => t.key === root.selected_key))
    readonly property var selected_tile: root.tiles[root.selected_index] || null
    readonly property bool carrying: root.picked.length > 0
    readonly property var picked_set: root.to_set(root.picked)
    readonly property var mark_numbers: {
        const out = {};
        root.marks.forEach((k, i) => out[k] = i + 1);
        return out;
    }
    readonly property var nav_order: Layout.flat(Layout.flat(Layout.bands(root.groups)).map(g => root.groups[g].tiles))
    readonly property int hit_index: Math.min(root.hit, root.ranked.length - 1)
    readonly property var hit_entry: root.ranked[root.hit_index] || null
    readonly property int match_count: root.ranked.length
    readonly property real list_width: root.typing ? Math.min(Style.px(460), frame.body.width * 0.34) : 0

    readonly property var metrics: ({
        gap: Style.px(10),
        pad: Style.px(10),
        label: Style.fs(-3) + Style.px(12),
        group_gap: Style.px(22),
        strip: Style.px(150)
    })
    readonly property var layout: Layout.compute(root.filmstrip, root.groups, root.tiles, frame.body.width - root.list_width, frame.body.height, root.metrics, root.selected_index)
    readonly property bool animate_moves: root.filmstrip && Power.on_ac && root.reveal === 1

    default property alias content: content_slot.data
    property alias under_tiles: under_slot.data
    property alias overlay: overlay_slot.data

    signal tiles_synced

    onTilesChanged: {
        Layout.sync_keys(root.tile_slots, root.tiles.map(t => t.key));
        root.tiles_synced();
    }

    screen: Quickshell.screens.find(s => s.name === root.held_screen_name) || null
    visible: false
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: root.layer_namespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function hold_focused_screen() {
        Popups.close();
        const mon = Hyprland.focusedMonitor;
        const target = (mon && Quickshell.screens.find(s => s.name === mon.name)) || Quickshell.screens[0];
        root.held_screen_name = target ? target.name : "";
        return mon;
    }

    function reset_common() {
        root.picked = [];
        root.from_search = false;
        root.marks = [];
        root.help_open = false;
        digit_timer.stop();
        root.clear_filter();
    }

    function reveal_open() {
        reveal_anim.stop();
        if (Power.on_ac) {
            reveal_anim.to = 1;
            reveal_anim.start();
        } else {
            root.reveal = 1;
        }
        keys.forceActiveFocus();
    }

    // Call after clearing wanted; immediate hides at once instead of fading.
    function conceal(immediate) {
        root.typing = false;
        root.help_open = false;
        reveal_anim.stop();
        if (immediate) {
            root.reveal = 0;
            root.visible = false;
        } else if (Power.on_ac && root.visible) {
            reveal_anim.to = 0;
            reveal_anim.start();
        } else {
            root.reveal = 0;
            root.visible = false;
        }
    }

    function focus_later(address) {
        focus_timer.address = address;
        focus_timer.restart();
    }

    function stop_digits() {
        digit_timer.stop();
    }

    function reading_order(items) {
        return items.slice().sort((a, b) => a.ry - b.ry || a.rx - b.rx);
    }

    function rank(entries, query) {
        const terms = Fuzzy.terms_of(query);
        if (terms.length === 0) return entries;
        const scored = [];
        for (const e of entries) {
            const s = Fuzzy.score_item(terms, e);
            if (s) scored.push({ entry: e, score: s.score });
        }
        scored.sort((a, b) => b.score - a.score || a.entry.recency - b.entry.recency);
        return scored.map(s => s.entry);
    }

    function set_hit(i) {
        root.hit = i;
        root.select_entry(root.hit_entry);
    }

    function step_hit(delta) {
        const n = root.ranked.length;
        if (n > 0) root.set_hit((root.hit_index + delta + n) % n);
    }

    function move(dx, dy) {
        const from = root.selected_index;
        let to = -1;
        if (root.filmstrip) {
            const order = root.layout.order;
            if (dx !== 0) {
                const at = order.indexOf(from);
                to = at >= 0 ? order[at + dx] : -1;
            } else {
                root.filmstrip_vertical(dy);
                return;
            }
        } else {
            to = Layout.neighbor(root.layout.tile_rects, from, dx, dy);
        }
        if (to !== undefined && to >= 0) root.select(to);
    }

    function cursor_key() {
        return root.selected_key + "|" + root.cursor_sub;
    }
    function play_if_moved(before) {
        if (root.cursor_key() !== before) ThemeAudio.play("cursor");
    }

    // Digits typed in quick succession name one target, so 1 then 2 lands on 12 when it exists.
    function type_digit(d) {
        const before = root.cursor_key();
        const joined = digit_timer.running ? digit_timer.typed + d : "";
        if (joined !== "" && root.jump(parseInt(joined))) {
            digit_timer.typed = joined;
        } else if (d !== "0" || root.zero_digit_jumps) {
            root.jump(parseInt(d));
            digit_timer.typed = d;
        } else {
            return;
        }
        root.play_if_moved(before);
        digit_timer.restart();
    }

    function to_set(list) {
        const out = {};
        for (const k of list) out[k] = true;
        return out;
    }

    function start_filter(from_search) {
        root.from_search = from_search;
        root.typing = true;
        filter_input.forceActiveFocus();
        filter_input.cursorPosition = filter_input.text.length;
        root.reset_hit();
    }

    function clear_filter() {
        root.typing = false;
        filter_input.text = "";
        if (root.visible) keys.forceActiveFocus();
    }

    function show_help() {
        root.help_open = true;
        key_help.forceActiveFocus();
    }

    function hide_help() {
        root.help_open = false;
        if (root.typing) filter_input.forceActiveFocus();
        else keys.forceActiveFocus();
    }

    function is_help_key(event) {
        return event.key === Qt.Key_Question || event.text === "?";
    }

    function direction_of(k) {
        if (k === Qt.Key_H || k === Qt.Key_Left) return [-1, 0];
        if (k === Qt.Key_L || k === Qt.Key_Right) return [1, 0];
        if (k === Qt.Key_K || k === Qt.Key_Up) return [0, -1];
        if (k === Qt.Key_J || k === Qt.Key_Down) return [0, 1];
        return null;
    }

    function handle_key(event) {
        const before = root.cursor_key();
        const k = event.key;
        if (event.modifiers & Qt.AltModifier) return;
        const pre = root.pre_key(event);
        if (pre === "stop") return;
        if (pre === "done") {
            event.accepted = true;
            return;
        }
        if (root.is_help_key(event)) {
            root.show_help();
        } else if (k === Qt.Key_Escape) {
            ThemeAudio.play("cancel");
            if (root.carrying) root.cancel_pick();
            else if (root.marks.length > 0) root.marks = [];
            else if (root.query !== "") root.clear_filter();
            else root.dismiss();
        } else if (k === Qt.Key_Q) {
            ThemeAudio.play("cancel");
            root.dismiss();
        } else if (root.direction_of(k)) {
            const dir = root.direction_of(k);
            root.move(dir[0], dir[1]);
            root.play_if_moved(before);
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            ThemeAudio.play("confirm");
            if (root.carrying) root.drop();
            else root.activate();
        } else if (k === Qt.Key_M) {
            ThemeAudio.play("confirm");
            if (root.carrying) root.drop();
            else root.pick();
        } else if (!root.carrying && (k === Qt.Key_Space || (k === Qt.Key_V && !(event.modifiers & Qt.ShiftModifier)))) {
            root.toggle_mark();
            ThemeAudio.play("confirm");
        } else if (!root.carrying && k === Qt.Key_V) {
            root.toggle_mark_all();
            ThemeAudio.play("confirm");
        } else if (!root.carrying && k === Qt.Key_X) {
            root.close_selected();
            ThemeAudio.play("confirm");
        } else if (k === Qt.Key_F) {
            root.filmstrip = !root.filmstrip;
        } else if (k === Qt.Key_Slash || event.text === "/") {
            root.start_filter(false);
        } else if (k >= Qt.Key_0 && k <= Qt.Key_9) {
            root.type_digit(String(k - Qt.Key_0));
        } else if (!root.extra_key(event, before)) {
            return;
        }
        event.accepted = true;
    }

    NumberAnimation {
        id: reveal_anim
        target: root
        property: "reveal"
        duration: 170
        easing.type: Easing.OutCubic
        onFinished: if (!root.wanted) root.visible = false
    }

    Timer {
        id: digit_timer
        property string typed: ""
        interval: 600
    }

    // Focus waits for the overlay to drop its exclusive keyboard grab, else the grab's release restores the old window.
    Timer {
        id: focus_timer
        property string address: ""
        interval: 60
        onTriggered: WindowState.focus(focus_timer.address)
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.alpha(Theme.bg_crust, 0.6)
        opacity: root.reveal

        MouseArea {
            anchors.fill: parent
            onClicked: {
                ThemeAudio.play("cancel");
                root.dismiss();
            }
        }
    }

    OverviewFrame {
        id: frame
        x: Style.px(36)
        y: Style.px(30)
        width: parent.width - x * 2
        height: parent.height - y * 2
        opacity: root.reveal
        scale: 0.97 + 0.03 * root.reveal
        title: root.title
        status: root.status_text
        status_color: root.status_accent ? Style.text_accent : Style.text_muted
        footer: root.footer_text

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => root.handle_key(event)
        }

        TextInput {
            id: filter_input
            width: 0
            height: 0
            opacity: 0
            maximumLength: 64
            onTextChanged: {
                root.query = text;
                if (root.typing) root.reset_hit();
            }
            Keys.onPressed: event => {
                const before = root.cursor_key();
                const k = event.key;
                if (root.is_help_key(event)) {
                    root.show_help();
                } else if (k === Qt.Key_Escape) {
                    ThemeAudio.play("cancel");
                    if (root.from_search && root.query === "") root.dismiss();
                    else root.clear_filter();
                } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                    ThemeAudio.play("confirm");
                    root.accept_hit();
                } else if (k === Qt.Key_Tab || k === Qt.Key_Down) {
                    root.step_hit(1);
                    root.play_if_moved(before);
                } else if (k === Qt.Key_Backtab || k === Qt.Key_Up) {
                    root.step_hit(-1);
                    root.play_if_moved(before);
                } else if (k === Qt.Key_Backspace && filter_input.text === "") {
                    ThemeAudio.play("cancel");
                    root.clear_filter();
                } else {
                    return;
                }
                event.accepted = true;
            }
        }

        Repeater {
            model: root.groups

            Item {
                id: group
                required property var modelData
                required property int index
                readonly property var rect: root.layout.group_rects[group.index] || ({ x: 0, y: 0, w: 0, h: 0 })
                readonly property bool holds_selection: !!root.selected_tile && root.selected_tile.group === group.index

                x: group.rect.x
                y: group.rect.y
                width: group.rect.w
                height: group.rect.h

                Behavior on x {
                    enabled: root.animate_moves
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    visible: !root.filmstrip
                    anchors.fill: parent
                    radius: Style.radius(8)
                    color: Qt.alpha(Theme.bg_mantle, 0.5)
                    border.width: 1
                    border.color: group.holds_selection ? Qt.alpha(Style.caret_color, 0.6) : Qt.alpha(Theme.ui_border, 0.6)
                }

                Dither {
                    visible: !root.filmstrip && color.a > 0
                    anchors.fill: parent
                    anchors.margins: 1
                    color: Style.dither
                    radius: Style.radius(8)
                    top_radius: Style.radius(8)
                }

                Rectangle {
                    visible: root.filmstrip
                    y: root.metrics.label - Style.px(4)
                    width: parent.width
                    height: 1
                    color: group.holds_selection ? Style.caret_color : Theme.ui_border
                }

                Item {
                    x: root.metrics.pad
                    y: root.filmstrip ? 0 : Style.px(6)
                    width: parent.width - root.metrics.pad * 2
                    height: section.implicitHeight
                    clip: true

                    MenuSection {
                        id: section
                        label: root.group_label(group.modelData, group.index)
                        color: group.holds_selection ? Style.text_primary : Style.section_fg
                    }
                }
            }
        }

        Item {
            id: under_slot
            anchors.fill: parent
        }

        Item {
            id: content_slot
            anchors.fill: parent
        }

        SearchList {
            visible: root.typing
            x: frame.body.width - width
            width: root.list_width
            height: frame.body.height
            entries: root.ranked
            current: root.hit_index
            onChosen: index => {
                root.set_hit(index);
                root.accept_hit();
            }
        }

        Item {
            id: overlay_slot
            anchors.fill: parent
        }

        // The full key list for the current mode, drawn over the tiles.
        Rectangle {
            visible: root.help_open
            anchors.fill: parent
            color: Style.frame_color.a > 0.5 ? Style.frame_color : Theme.bg_crust

            KeyHelp {
                id: key_help
                anchors.fill: parent
                text: root.help_text
                general: [{ key: "?", desc: "back" }, { key: "Esc", desc: "back" }, { key: "q", desc: root.help_close_desc }]
                onBack: root.hide_help()
                onClose_requested: root.dismiss()
            }
        }
    }
}
