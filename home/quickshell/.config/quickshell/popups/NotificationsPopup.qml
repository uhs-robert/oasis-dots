// home/quickshell/.config/quickshell/popups/NotificationsPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import "../components"
import "../theme"
import "../services"
import "notifications"

Popup {
    id: root

    popup_name: "notifications"
    size_class: "large"
    preferred_width: 420
    fit_island: true
    body_height: content.implicitHeight + 24

    readonly property int content_height: Style.px(460)
    tabs: ["All", "Apps", "Critical"]
    // The sub-view is the tab's sort order; Popup keeps each tab's choice across tab switches.
    readonly property var app_sort_names: ["Latest activity", "By name"]
    readonly property var time_sort_names: ["Newest first", "Oldest first"]
    sub_views: root.current_tab === 1 ? root.app_sort_names : root.time_sort_names
    jumps_enabled: true

    property int selected: 0
    // -1 is the card body; 0.. are the selected card's action buttons.
    property int action_index: -1

    readonly property bool is_open: Popups.open_name === "notifications"
    onIs_openChanged: if (is_open) {
        root.selected = 0;
        root.action_index = -1;
        NotificationState.mark_read();
    }
    onCurrent_tabChanged: root.selected = 0
    onSelectedChanged: root.action_index = -1
    onJump_first: root.go_first()
    onJump_last: root.go_last()

    function day_label(ms) {
        const d = new Date(ms);
        const now = new Date();
        const d0 = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const t0 = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const diff_days = Math.round((t0 - d0) / 86400000);
        if (diff_days === 0) return "Today";
        if (diff_days === 1) return "Yesterday";
        return Qt.formatDate(d, "dddd, MMM d");
    }

    // --- Rows: a flat, typed list the ListView renders directly (day/app headers mixed with entries) ---

    function build_all_rows() {
        const entries = root.current_sub === 0 ? NotificationState.history.slice() : NotificationState.history.slice().reverse();
        const rows = [];
        let last_label = null;
        for (const e of entries) {
            const label = root.day_label(e.time);
            if (label !== last_label) {
                rows.push({ type: "day", label: label });
                last_label = label;
            }
            rows.push({ type: "entry", entry: e });
        }
        return rows;
    }

    function build_apps_rows() {
        const groups = Object.create(null);
        for (const e of NotificationState.history) {
            const name = e.notification ? e.notification.appName : "Unknown";
            const icon = e.notification ? e.notification.appIcon : "";
            if (!groups[name]) groups[name] = { name: name, icon: icon, entries: [] };
            groups[name].entries.push(e);
        }
        const group_list = Object.values(groups);
        for (const g of group_list) g.entries.sort((a, b) => b.time - a.time);
        if (root.current_sub === 0) group_list.sort((a, b) => (b.entries[0] ? b.entries[0].time : 0) - (a.entries[0] ? a.entries[0].time : 0));
        else group_list.sort((a, b) => a.name.localeCompare(b.name));

        const rows = [];
        for (const g of group_list) {
            rows.push({ type: "app_header", name: g.name, icon: g.icon, count: g.entries.length });
            for (const e of g.entries) rows.push({ type: "entry", entry: e });
        }
        return rows;
    }

    function build_critical_rows() {
        const critical = NotificationState.history.filter(e => e.notification && e.notification.urgency === NotificationUrgency.Critical);
        const entries = root.current_sub === 0 ? critical : critical.reverse();
        return entries.map(e => ({ type: "entry", entry: e }));
    }

    readonly property var rows: root.current_tab === 0 ? root.build_all_rows() : root.current_tab === 1 ? root.build_apps_rows() : root.build_critical_rows()
    readonly property var entry_rows: root.rows.filter(r => r.type === "entry")

    onEntry_rowsChanged: root.selected = Math.max(0, Math.min(root.selected, root.entry_rows.length - 1))

    function scroll_to_selected() {
        const sel = root.entry_rows[root.selected];
        if (!sel) return;
        const idx = root.rows.findIndex(r => r.type === "entry" && r.entry === sel.entry);
        if (idx >= 0) row_list.positionViewAtIndex(idx, ListView.Contain);
    }

    function move_selected(delta) {
        if (root.entry_rows.length === 0) return;
        root.selected = Math.max(0, Math.min(root.entry_rows.length - 1, root.selected + delta));
        root.scroll_to_selected();
    }

    function go_first() {
        root.selected = 0;
        root.scroll_to_selected();
    }

    function go_last() {
        root.selected = Math.max(0, root.entry_rows.length - 1);
        root.scroll_to_selected();
    }

    function select_entry(entry) {
        const idx = root.entry_rows.findIndex(r => r.entry.id === entry.id);
        if (idx >= 0) root.selected = idx;
    }

    function dismiss_selected() {
        const sel = root.entry_rows[root.selected];
        if (sel) NotificationState.dismiss(sel.entry);
    }

    function actions_of(entry) {
        const all = entry && entry.notification && entry.notification.actions ? entry.notification.actions : [];
        const list = [];
        for (let i = 0; i < all.length; i++) if (all[i].identifier !== "default") list.push(all[i]);
        return list;
    }

    function move_action(delta) {
        const sel = root.entry_rows[root.selected];
        const count = sel ? root.actions_of(sel.entry).length : 0;
        root.action_index = Math.max(-1, Math.min(count - 1, root.action_index + delta));
    }

    function invoke_selected() {
        const sel = root.entry_rows[root.selected];
        if (!sel) return;
        const actions = root.actions_of(sel.entry);
        if (root.action_index >= 0 && root.action_index < actions.length) NotificationState.invoke_action(sel.entry, actions[root.action_index]);
        else NotificationState.invoke_default(sel.entry);
        Popups.close();
    }

    function handle_key(event) {
        if (event.key === Qt.Key_J) {
            root.move_selected(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_K) {
            root.move_selected(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_L) {
            root.move_action(event.modifiers & Qt.ShiftModifier ? 99 : 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_H) {
            root.move_action(event.modifiers & Qt.ShiftModifier ? -99 : -1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.invoke_selected();
            event.accepted = true;
        } else if (event.key === Qt.Key_T || (event.key === Qt.Key_D && (event.modifiers & Qt.ShiftModifier))) {
            NotificationState.toggle_dnd();
            event.accepted = true;
        } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ShiftModifier)) {
            NotificationState.clear_all();
            event.accepted = true;
        } else if (event.key === Qt.Key_D || event.key === Qt.Key_X) {
            root.dismiss_selected();
            event.accepted = true;
        }
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        implicitHeight: main_column.implicitHeight
        clip: true
        focus: true

        Keys.onPressed: event => root.handle_key(event)

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 8

            // --- Header: buttons beside the title when it still fits, else on their own row (stacked if even a pair won't fit) ---
            GridLayout {
                id: header
                readonly property real info_width: (bell.visible ? bell.implicitWidth + 14 : 0) + Math.max(title_text.visible ? title_text.implicitWidth : 0, count_text.implicitWidth)
                readonly property real pair_width: dnd_button.implicitWidth + header.columnSpacing + clear_button.implicitWidth
                readonly property bool buttons_inline: header.width >= header.info_width + header.columnSpacing + header.pair_width
                readonly property bool buttons_pair: header.width >= header.pair_width

                Layout.fillWidth: true
                columns: header.buttons_inline ? 3 : header.buttons_pair ? 2 : 1
                columnSpacing: 8
                rowSpacing: 6

                RowLayout {
                    Layout.columnSpan: header.buttons_inline ? 1 : header.columns
                    Layout.fillWidth: true
                    spacing: 14

                    // The style's title tab already names the popup.
                    Text {
                        id: bell
                        visible: !Style.show_title
                        text: NotificationState.dnd ? "\u{f009b}" : "\u{f009a}"
                        color: NotificationState.dnd ? Style.text_dim : Theme.theme_primary
                        font.family: Style.font_family
                        font.pixelSize: 40
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0

                        Text {
                            id: title_text
                            visible: !Style.show_title
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: "Notifications"
                            color: Theme.fg_core
                            font.bold: true
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size + 6
                        }

                        Text {
                            id: count_text
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: NotificationState.unread + " unread · " + NotificationState.history.length + " total"
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - 2
                        }
                    }
                }

                HeaderButton {
                    id: dnd_button
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: !header.buttons_inline
                    icon: "\u{f009b}"
                    label: "DND"
                    key_hint: Style.row_keys ? "t" : "D"
                    active: NotificationState.dnd
                    onActivated: NotificationState.toggle_dnd()
                }

                HeaderButton {
                    id: clear_button
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: !header.buttons_inline
                    icon: "\u{f0a7a}"
                    label: "Clear all"
                    key_hint: "C"
                    onActivated: NotificationState.clear_all()
                }
            }

            TabRows {
                Layout.fillWidth: true
                labels: root.tabs
                current: root.current_tab
                font_size: Style.font_size - 1
                tab_height: Style.px(28)
                onPicked: i => root.set_tab(i)
            }

            // --- Content: fixed height so the panel never resizes as entries change ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.content_height

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.rows.length === 0
                    spacing: 6

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: NotificationState.dnd ? "\u{f009b}" : "\u{f009a}"
                        color: Style.text_dim
                        font.family: Style.font_family
                        font.pixelSize: 48
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.current_tab === 2 ? "Nothing critical" : "All caught up"
                        color: Style.text_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size
                    }
                }

                ListView {
                    id: row_list
                    anchors.fill: parent
                    visible: root.rows.length > 0
                    clip: true
                    spacing: 6
                    model: root.rows

                    delegate: Item {
                        id: row_item
                        required property var modelData

                        width: ListView.view.width
                        height: row_item.modelData.type === "day" ? day_text.implicitHeight + 6 : row_item.modelData.type === "app_header" ? app_header.implicitHeight + 4 : card.implicitHeight
                        clip: true

                        Text {
                            id: day_text
                            visible: row_item.modelData.type === "day"
                            width: parent.width
                            elide: Text.ElideRight
                            text: row_item.modelData.type !== "day" ? "" : Style.section_rule ? "── " + row_item.modelData.label + " " + "─".repeat(160) : row_item.modelData.label
                            color: Style.text_dim
                            font.bold: true
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - 2
                        }

                        RowLayout {
                            id: app_header
                            visible: row_item.modelData.type === "app_header"
                            width: parent.width
                            spacing: 8

                            Image {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                visible: row_item.modelData.type === "app_header" && row_item.modelData.icon !== ""
                                source: row_item.modelData.type === "app_header" ? Quickshell.iconPath(row_item.modelData.icon, true) : ""
                                fillMode: Image.PreserveAspectFit
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                text: row_item.modelData.type === "app_header" ? row_item.modelData.name + "  ·  " + row_item.modelData.count : ""
                                color: Style.text_muted
                                font.bold: true
                                font.family: Style.font_family
                                font.pixelSize: Style.font_size - 1
                            }
                        }

                        NotificationCard {
                            id: card
                            visible: row_item.modelData.type === "entry"
                            width: row_item.width
                            entry: row_item.modelData.type === "entry" ? row_item.modelData.entry : null
                            selected: !!(row_item.modelData.type === "entry" && root.entry_rows[root.selected] && root.entry_rows[root.selected].entry.id === row_item.modelData.entry.id)
                            focused_action: card.selected ? root.action_index : -1
                            onSelect_requested: root.select_entry(row_item.modelData.entry)
                            onInvoke_requested: {
                                NotificationState.invoke_default(row_item.modelData.entry);
                                Popups.close();
                            }
                        }
                    }
                }
            }

            // --- Sub-view pills: per-tab sort order, under the content; a click flips the order ---
            TabRows {
                Layout.fillWidth: true
                chips: true
                labels: root.sub_views
                current: root.current_sub
                reserve_labels: [root.app_sort_names, root.time_sort_names]
                onPicked: root.step_sub(1)
            }

            MenuFooter {
                Layout.fillWidth: true
                wrap: true
                text: "[ ] tabs · 1-3 select · Tab order · j/k move · gg/G first/last · h/l action · H/L body/last · Enter open · d/x dismiss · C clear all · t dnd"
            }
        }
    }
}
