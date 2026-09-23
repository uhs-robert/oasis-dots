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
    preferred_width: 640
    implicitHeight: content.implicitHeight + 24

    readonly property int content_height: 460
    readonly property var tab_names: ["All", "Apps", "Critical"]

    // 0/1/2: independent per tab so switching tabs keeps each one's chosen order.
    property int order_all: 0
    property int order_apps: 0
    property int order_critical: 0

    property int current_tab: 0
    property int selected: 0
    property double last_g_ms: 0

    readonly property bool is_open: Popups.open_name === "notifications"
    onIs_openChanged: if (is_open) {
        root.selected = 0;
        NotificationState.mark_read();
    }
    onCurrent_tabChanged: root.selected = 0

    function set_tab(i) {
        root.current_tab = Math.max(0, Math.min(root.tab_names.length - 1, i));
    }

    function step_tab(delta) {
        root.current_tab = (root.current_tab + delta + root.tab_names.length) % root.tab_names.length;
    }

    function step_order() {
        if (root.current_tab === 0) root.order_all = root.order_all === 0 ? 1 : 0;
        else if (root.current_tab === 1) root.order_apps = root.order_apps === 0 ? 1 : 0;
        else root.order_critical = root.order_critical === 0 ? 1 : 0;
    }

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
        const entries = root.order_all === 0 ? NotificationState.history.slice() : NotificationState.history.slice().reverse();
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
        if (root.order_apps === 0) group_list.sort((a, b) => (b.entries[0] ? b.entries[0].time : 0) - (a.entries[0] ? a.entries[0].time : 0));
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
        const entries = root.order_critical === 0 ? critical : critical.reverse();
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
        const idx = root.entry_rows.findIndex(r => r.entry === entry);
        if (idx >= 0) root.selected = idx;
    }

    function dismiss_selected() {
        const sel = root.entry_rows[root.selected];
        if (sel) NotificationState.dismiss(sel.entry);
    }

    function invoke_selected() {
        const sel = root.entry_rows[root.selected];
        if (sel) NotificationState.invoke_default(sel.entry);
    }

    function handle_key(event) {
        if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            root.step_order();
            event.accepted = true;
        } else if (event.key === Qt.Key_Tab) {
            root.step_order();
            event.accepted = true;
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_1 + root.tab_names.length - 1) {
            root.set_tab(event.key - Qt.Key_1);
            event.accepted = true;
        } else if (event.key === Qt.Key_BracketLeft) {
            root.step_tab(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_BracketRight) {
            root.step_tab(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_J) {
            root.move_selected(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_K) {
            root.move_selected(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_G) {
            if (event.modifiers & Qt.ShiftModifier) {
                root.go_last();
            } else {
                const now_ms = Date.now();
                if (now_ms - root.last_g_ms < 500) { root.go_first(); root.last_g_ms = 0; }
                else root.last_g_ms = now_ms;
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.invoke_selected();
            event.accepted = true;
        } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ShiftModifier)) {
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
        Keys.onTabPressed: event => root.handle_key(event)
        Keys.onBacktabPressed: event => root.handle_key(event)

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 8

            // --- Header ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Text {
                    text: NotificationState.dnd ? "\u{f009b}" : "\u{f009a}"
                    color: NotificationState.dnd ? Theme.fg_dim : Theme.theme_primary
                    font.family: Theme.font_family
                    font.pixelSize: 40
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: "Notifications"
                        color: Theme.fg_core
                        font.bold: true
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size + 6
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: NotificationState.unread + " unread · " + NotificationState.history.length + " total"
                        color: Theme.fg_muted
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size - 2
                    }
                }

                HeaderButton {
                    Layout.alignment: Qt.AlignVCenter
                    icon: "\u{f009b}"
                    label: "Do not disturb"
                    key_hint: "D"
                    active: NotificationState.dnd
                    onActivated: NotificationState.toggle_dnd()
                }

                HeaderButton {
                    Layout.alignment: Qt.AlignVCenter
                    icon: "\u{f0a7a}"
                    label: "Clear all"
                    key_hint: "C"
                    onActivated: NotificationState.clear_all()
                }
            }

            // --- Tab row ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: root.tab_names

                    Rectangle {
                        id: tab_chip
                        required property string modelData
                        required property int index

                        Layout.fillWidth: true
                        height: 28
                        radius: 4
                        color: tab_chip.index === root.current_tab ? Theme.bg_surface : "transparent"

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: tab_chip.modelData
                            color: tab_chip.index === root.current_tab ? Theme.theme_secondary : Theme.fg_muted
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size - 1
                            font.bold: tab_chip.index === root.current_tab
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.set_tab(tab_chip.index)
                        }
                    }
                }
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
                        color: Theme.fg_dim
                        font.family: Theme.font_family
                        font.pixelSize: 48
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.current_tab === 2 ? "Nothing critical" : "All caught up"
                        color: Theme.fg_dim
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size
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
                            text: row_item.modelData.type === "day" ? row_item.modelData.label : ""
                            color: Theme.fg_dim
                            font.bold: true
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size - 2
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
                                color: Theme.fg_muted
                                font.bold: true
                                font.family: Theme.font_family
                                font.pixelSize: Theme.popup_font_size - 1
                            }
                        }

                        NotificationCard {
                            id: card
                            visible: row_item.modelData.type === "entry"
                            width: row_item.width
                            entry: row_item.modelData.type === "entry" ? row_item.modelData.entry : null
                            selected: !!(row_item.modelData.type === "entry" && root.entry_rows[root.selected] && root.entry_rows[root.selected].entry === row_item.modelData.entry)
                            onSelect_requested: root.select_entry(row_item.modelData.entry)
                            onInvoke_requested: NotificationState.invoke_default(row_item.modelData.entry)
                        }
                    }
                }
            }

            // --- Sub-view pills: per-tab sort order, under the content ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 28

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: root.current_tab === 1 ? ["Latest activity", "By name"] : ["Newest first", "Oldest first"]

                        Rectangle {
                            id: sub_chip
                            required property string modelData
                            required property int index
                            readonly property int current_order: root.current_tab === 0 ? root.order_all : root.current_tab === 1 ? root.order_apps : root.order_critical
                            readonly property bool active: sub_chip.index === sub_chip.current_order

                            implicitWidth: sub_label.implicitWidth + 20
                            implicitHeight: 24
                            radius: 12
                            color: sub_chip.active ? Theme.bg_surface : "transparent"

                            Text {
                                id: sub_label
                                anchors.centerIn: parent
                                text: sub_chip.modelData
                                color: sub_chip.active ? Theme.theme_secondary : Theme.fg_muted
                                font.bold: sub_chip.active
                                font.family: Theme.font_family
                                font.pixelSize: Theme.popup_font_size - 3
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.step_order()
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: "[ ] tabs · 1-3 select · Tab order · j/k move · gg/G first/last · Enter open · d/x dismiss · C clear all · D dnd"
                color: Theme.fg_dim
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size - 4
            }
        }
    }
}
