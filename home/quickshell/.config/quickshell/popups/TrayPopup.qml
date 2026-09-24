// home/quickshell/.config/quickshell/popups/TrayPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Hyprland
import Quickshell.Widgets
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "tray"
    preferred_width: 300
    footer_hint: "j/k move · Enter open · m/l menu · q close"
    body_height: content.implicitHeight + 24

    readonly property var items: SystemTray.items.values

    property int selected: 0
    onItemsChanged: if (selected >= items.length) selected = Math.max(0, items.length - 1);

    readonly property bool is_open: Popups.open_name === "tray"
    onIs_openChanged: if (is_open) root.selected = 0

    function norm(str) {
        return (str || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    // Tray ids and window classes rarely match exactly (Betterbird_systray_icon vs eu.betterbird.Betterbird).
    function window_for(item_data) {
        const id = norm(item_data.id).replace(/systrayicon$|trayicon$|tray$/, "");
        const title = norm(item_data.title);
        for (const t of Hyprland.toplevels.values) {
            const cls = norm(t.lastIpcObject && t.lastIpcObject.class ? t.lastIpcObject.class : (t.wayland ? t.wayland.appId : ""));
            if (!cls) continue;
            if (cls === id || cls === title || (id.length >= 3 && (cls.includes(id) || id.includes(cls)))) return t;
        }
        return null;
    }

    // Some apps put status text in the title (Betterbird: "1 unread message\nInbox: 1").
    function app_name(item_data) {
        const title = item_data.title || "";
        if (title && title.indexOf("\n") < 0 && title.length <= 24) return title;
        const id = (item_data.id || "").replace(/[_-]?(systray|tray)[_-]?icon$/i, "");
        return id ? id.charAt(0).toUpperCase() + id.slice(1) : title.split("\n")[0];
    }

    function detail(item_data) {
        const line = (item_data.tooltipTitle || item_data.title || "").split("\n")[0];
        return line === root.app_name(item_data) ? "" : line;
    }

    function focus_window(t) {
        Hyprland.dispatch("hl.dsp.focus({ window = 'address:0x" + t.address + "' })");
    }

    function activate_row(item_data) {
        if (!item_data) return;
        if (item_data.onlyMenu) {
            root.open_menu(item_data, item_repeater.itemAt(root.items.indexOf(item_data)));
            return;
        }
        Popups.close();
        const win = root.window_for(item_data);
        if (win) {
            root.focus_window(win);
            return;
        }
        item_data.activate();
        refocus_timer.item_data = item_data;
        refocus_timer.restart();
    }

    // An app hidden to the tray has no window until activate() maps it.
    Timer {
        id: refocus_timer
        property var item_data: null
        interval: 400
        onTriggered: {
            Hyprland.refreshToplevels();
            const win = item_data ? root.window_for(item_data) : null;
            if (win) root.focus_window(win);
        }
    }

    QsMenuAnchor {
        id: menu_anchor
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.FlipX | PopupAdjustment.FlipY
        onClosed: root.suspend_grab = false
    }

    // Anchored to the row inside this popup so it opens next to it; the popup stays open underneath.
    function open_menu(item_data, source_item) {
        if (!item_data || !item_data.hasMenu || !source_item) return;
        if (menu_anchor.visible) menu_anchor.close();
        root.suspend_grab = true;
        menu_anchor.menu = item_data.menu;
        menu_anchor.anchor.item = source_item;
        Qt.callLater(() => {
            if (!menu_anchor.visible) menu_anchor.open();
        });
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: main_column.implicitHeight
        focus: true

        Keys.onPressed: event => {
            const item_data = root.items[root.selected];
            if (event.key === Qt.Key_J) {
                root.selected = Math.min(root.items.length - 1, root.selected + 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = Math.max(0, root.selected - 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activate_row(item_data);
                event.accepted = true;
            } else if (event.key === Qt.Key_M || event.key === Qt.Key_L) {
                root.open_menu(item_data, item_repeater.itemAt(root.selected));
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 2

            Text {
                visible: root.items.length === 0
                text: "No tray apps"
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size - 2
            }

            Repeater {
                id: item_repeater
                model: root.items

                MenuRow {
                    id: item_row
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    height: Style.px(26)
                    selected: item_row.index === root.selected

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6 + item_row.inset
                        anchors.rightMargin: 6 + item_row.key_space
                        spacing: 8

                        IconImage {
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            implicitSize: 16
                            source: item_row.modelData.icon
                        }

                        Text {
                            text: root.app_name(item_row.modelData)
                            color: item_row.fg(root.st.text_fg)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size - 1
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            wrapMode: Text.NoWrap
                            text: root.detail(item_row.modelData)
                            color: item_row.fg(root.st.text_dim)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size - 3
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: mouse => {
                            root.selected = item_row.index;
                            if (mouse.button === Qt.RightButton) {
                                root.open_menu(item_row.modelData, item_row);
                            } else if (mouse.button === Qt.MiddleButton) {
                                item_row.modelData.secondaryActivate();
                                Popups.close();
                            } else {
                                root.activate_row(item_row.modelData);
                            }
                        }
                    }
                }
            }
        }
    }
}
