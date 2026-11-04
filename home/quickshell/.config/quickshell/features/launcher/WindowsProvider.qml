import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.core
import qs.ui
import qs.theme
import qs.features.popups
import qs.features.windows
import "../../core/Fuzzy.js" as Fuzzy
import "../../core/WindowEntries.js" as WindowEntries

// Every Hyprland window, most recently focused first, special workspaces included. It opens on one-line rows with the
// window before the focused one selected, so Enter right away is Alt+Tab. `x` closes the window and `f` narrows the
// list to the focused monitor, then the focused workspace.
PickerProvider {
    id: root

    name: "windows"
    start_group: "browse"
    layout: "browse"
    default_preview_size: "m"
    default_browse_view: "list"
    card_size: Qt.size(248, 190)
    title: "Windows"
    placeholder: "Search windows by class, title or workspace"
    verb: "focus"
    rank_by_usage: false
    // Ties under a query, and the empty query, stay most recent first, as in the overview's search.
    keep_order: true
    actions: [{ key: "x", desc: "close window" }, { key: "f", desc: "filter", needs_item: false }]
    empty_text: root.filter === "all" ? "No windows open" : "No windows on this " + root.filter

    // "all", "monitor" or "workspace" (WindowEntries.js); every open starts at "all".
    property string filter: "all"
    // The focused monitor and workspace when the picker opened, which the filter narrows to.
    property var here: ({ monitor: "", ws_id: 0 })
    items: WindowState.entries().filter(e => WindowEntries.kept_by_filter(e, root.filter, root.here))
    initial_index: WindowEntries.previous_index(root.items, WindowState.active_address)
    status_text: WindowEntries.filter_label(root.filter)
    status_active: root.filter !== "all"
    // A battery keeps the preview to one frame, like the cards.
    readonly property bool preview_live: root.is_shown && PowerSource.on_ac

    property string focus_address: ""

    function refresh(arg) {
        root.filter = "all";
        const active = WindowState.find(WindowState.active_address);
        const ws = active && active.workspace ? active.workspace : Hyprland.focusedWorkspace;
        root.here = { monitor: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "", ws_id: ws ? ws.id : 0 };
        WindowState.refresh();
    }

    // Focused once now, which warps the cursor onto the window, and again once the picker's layer has unmapped: while
    // the popup holds the keyboard the focus does not stick, and the layer closing hands it back to the old window.
    function activate(item) {
        WindowState.focus(item.address);
        root.focus_address = item.address;
        focus_fallback.restart();
    }

    function refocus() {
        focus_fallback.stop();
        const address = root.focus_address;
        root.focus_address = "";
        // A popup opened since the picker closed keeps the keyboard.
        if (Popups.open_name === "") WindowState.focus(address);
    }

    function run_action(key, item) {
        if (key === "f") root.filter = WindowEntries.cycled_filter(root.filter);
        else if (key === "x") WindowState.close(item.address);
    }

    Connections {
        target: Hyprland
        enabled: root.focus_address !== ""
        function onRawEvent(event) {
            if (event.name === "closelayer" && event.data === "quickshell-popup") root.refocus();
        }
    }

    // In case closelayer never arrives, as Popups.after_close does.
    Timer {
        id: focus_fallback
        interval: 1000
        onTriggered: root.refocus()
    }

    // The selected window as large as fits, live on AC, with its title and class under it.
    preview: Component {
        Item {
            id: pane
            property var entry: null

            Rectangle {
                anchors.fill: parent
                radius: Style.radius(4)
                color: Theme.bg_core
            }

            WindowThumbnail {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: caption_title.top
                anchors.margins: 8
                visible: !!pane.entry
                toplevel: pane.entry ? pane.entry.toplevel : null
                icon_source: pane.entry ? WindowState.icon_for(pane.entry.toplevel) : ""
                active: root.is_shown
                live: root.preview_live
            }

            Text {
                id: caption_title
                anchors.left: parent.left
                anchors.right: caption_place.left
                anchors.bottom: caption_class.top
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                visible: !!pane.entry
                elide: Text.ElideRight
                text: pane.entry ? pane.entry.title : ""
                textFormat: Text.PlainText
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                font.bold: true
            }

            Text {
                id: caption_place
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: caption_title.verticalCenter
                visible: !!pane.entry
                text: pane.entry ? pane.entry.place.toUpperCase() : ""
                textFormat: Text.PlainText
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
                font.bold: true
            }

            Text {
                id: caption_class
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                visible: !!pane.entry
                elide: Text.ElideRight
                text: pane.entry ? pane.entry.label : ""
                textFormat: Text.PlainText
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }
    }

    // One still frame across the top, then the icon and title, then the class and workspace.
    card: Component {
        Item {
            id: card
            property var entry: ({})
            property var positions: []
            property bool selected: false

            WindowThumbnail {
                id: card_thumb
                width: parent.width
                height: parent.height - card_title.height - card_meta.height - 10
                toplevel: card.entry.toplevel || null
                icon_source: card.entry.toplevel ? WindowState.icon_for(card.entry.toplevel) : ""
                active: root.is_shown
                live: false
            }

            IconImage {
                id: card_icon
                anchors.verticalCenter: card_title.verticalCenter
                implicitSize: Style.px(14)
                asynchronous: true
                source: card.entry.toplevel ? WindowState.icon_for(card.entry.toplevel) : ""
            }

            Text {
                id: card_title
                anchors.top: card_thumb.bottom
                anchors.topMargin: 6
                anchors.left: card_icon.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                elide: Text.ElideRight
                text: card.entry.title || ""
                textFormat: Text.PlainText
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
                font.bold: true
            }

            // Short of the card's foot corner, where the quick-pick number sits. Matches highlight here: the class is the label.
            Text {
                id: card_meta
                anchors.top: card_title.bottom
                anchors.topMargin: 2
                width: parent.width - Style.px(16)
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: Fuzzy.highlight(card.entry.label || "", card.positions, String(Style.text_accent)) + " · " + Fuzzy.escape_html(card.entry.place || "")
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
            }
        }
    }

    // One line: the icon and title, then the class and workspace.
    row: Component {
        Item {
            id: line
            property var entry: ({})
            property var positions: []
            property bool selected: false

            IconImage {
                id: line_icon
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: Style.px(18)
                asynchronous: true
                source: line.entry.toplevel ? WindowState.icon_for(line.entry.toplevel) : ""
            }

            Text {
                id: line_title
                anchors.left: line_icon.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(implicitWidth, parent.width - x - Style.px(260)))
                elide: Text.ElideRight
                text: line.entry.title || ""
                textFormat: Text.PlainText
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
            }

            Text {
                anchors.left: line_title.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: Fuzzy.highlight(line.entry.label || "", line.positions, String(Style.text_accent)) + " · " + Fuzzy.escape_html(line.entry.place || "")
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
            }
        }
    }
}
