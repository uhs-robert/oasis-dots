import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme
import "FirefoxTabs.js" as FirefoxTabs
import "../../core/Fuzzy.js" as Fuzzy

// Every Firefox tab through DesertFox's bridge, grouped by window in tab-bar order or most recently used
// first (`s`, remembered in FirefoxTabsSettings): each card shows the tab's last captured image, refreshed a few tabs
// at a time after the list shows. Enter switches to the tab and focuses its window, `x` closes it, `y` copies its URL
// and `f` narrows the list to one window.
PickerProvider {
    id: root

    name: "firefox_tabs"
    start_group: "browse"
    layout: "browse"
    default_preview_size: "m"
    card_size: Qt.size(248, 190)
    default_browse_view: "list"
    grouped: root.sort === "tabs"
    title: "Browser tabs"
    placeholder: "Search tabs by title or address"
    verb: "switch"
    rank_by_usage: false
    keep_order: true
    actions: [{ key: "x", desc: "close tab" }, { key: "y", desc: "copy URL" }, { key: "f", desc: "window", needs_item: false }, { key: "s", desc: "sort", needs_item: false }]
    empty_text: root.host_state === "loading" ? "Loading tabs" : root.host_state === "unavailable" ? root.setup_hint : root.host_state === "sharing_off" ? root.sharing_off_hint : root.host_state === "error" ? "Firefox did not list its tabs: " + root.host_error : "No tabs open"

    // voxcmd's bridge client: it checks the socket is the user's own before trusting it, and also switches tabs,
    // raising the right window by the title nonce (DesertFox assumes no window manager), so the picker calls it rather
    // than talking to the socket itself.
    readonly property string firefox_tab: Quickshell.env("HOME") + "/.local/share/voxcmd/firefox-tab"
    readonly property string setup_hint: "Firefox tabs need DesertFox with its bridge on: set bridge and bridge_share_tabs to true in DesertFox"
    readonly property string sharing_off_hint: "DesertFox is not sharing its tabs: set bridge_share_tabs to true"
    readonly property int capture_batch_size: 4
    // A batch waits on Firefox drawing each tab; the default of 3 s is for one quick request.
    readonly property string capture_timeout_s: "30"

    // "loading", "ok", "unavailable" (no socket or no bridge answering), "sharing_off" (the bridge is up, tab sharing is
    // not) or "error".
    property string host_state: "loading"
    property string host_error: ""
    // Every listed tab in tab-bar order; `items` is the ones the window filter keeps, in the sort's order.
    property var entries: []
    readonly property var windows: FirefoxTabs.windows_of(root.entries)
    readonly property string sort: FirefoxTabs.sort_of(FirefoxTabsSettings.sort)
    // "all" or a window id; every open starts at "all".
    property var filter: "all"
    readonly property var shown_filter: root.windows.indexOf(root.filter) >= 0 ? root.filter : "all"
    items: FirefoxTabs.arranged(root.entries, root.sort, root.shown_filter, root.windows)
    property bool copied: false
    status_text: root.copied ? "URL COPIED" : root.entries.length > 0 ? FirefoxTabs.filter_label(root.shown_filter, root.windows) + " · " + FirefoxTabs.sort_labels[root.sort] : ""
    status_active: root.copied || root.shown_filter !== "all"

    // Tab id -> { thumbnail, thumbnail_at } from captures, newer than what the list named.
    property var thumbs: ({})
    property var capture_queue: []
    property var close_queue: []
    property bool close_failed: false

    // `timeout_s` overrides firefox-tab's own when given.
    function request_argv(request, timeout_s) {
        // Through sh so a missing firefox-tab is an empty answer, read as unreachable, rather than a process that never starts.
        return ["sh", "-c", "[ -z \"$2\" ] || export VOXCMD_FIREFOX_HOST_TIMEOUT=\"$2\"; exec \"$0\" request \"$1\"", root.firefox_tab, JSON.stringify(request), timeout_s || ""];
    }

    function group_of(item) {
        return item.window_id;
    }

    function group_title(window_id, shown) {
        return FirefoxTabs.group_title(window_id, shown.length, root.entries, root.windows);
    }

    function source_of(entry) {
        return entry && entry.id ? FirefoxTabs.thumbnail_source(FirefoxTabs.thumb_of(entry, root.thumbs)) : "";
    }

    function refresh(arg) {
        root.filter = "all";
        root.copied = false;
        root.capture_queue = [];
        if (root.entries.length === 0) root.host_state = "loading";
        list_proc.running = false;
        list_proc.command = root.request_argv({ verb: "tabs" });
        list_proc.running = true;
    }

    function listed(text) {
        const reply = FirefoxTabs.parse_reply(text);
        root.host_state = reply.state;
        root.host_error = reply.error;
        root.entries = reply.state === "ok" ? FirefoxTabs.items_of(reply.fields.tabs) : [];
        const ids = {};
        for (const e of root.entries) ids[e.id] = true;
        const kept = {};
        for (const id in root.thumbs) if (ids[id]) kept[id] = root.thumbs[id];
        root.thumbs = kept;
        // In the order the list shows them, so the top of it refreshes first.
        root.capture_queue = FirefoxTabs.capture_batches(FirefoxTabs.arranged(root.entries, root.sort, "all", root.windows), root.capture_batch_size);
        root.capture_next();
    }

    // One batch at a time, and only while the picker shows: a closed picker leaves the rest for the next open.
    function capture_next() {
        if (capture_proc.running || !root.is_shown) return;
        const open_ids = root.entries.map(e => e.tab_id);
        while (root.capture_queue.length > 0) {
            const batch = root.capture_queue[0].filter(id => open_ids.indexOf(id) >= 0);
            root.capture_queue = root.capture_queue.slice(1);
            if (batch.length === 0) continue;
            capture_proc.command = root.request_argv({ verb: "capture", tab_ids: batch }, root.capture_timeout_s);
            capture_proc.running = true;
            return;
        }
    }

    // The tab the preview shows jumps the queue, so the image looked at refreshes first.
    function capture_first(entry) {
        if (!entry || entry.discarded || !root.capture_queue.some(batch => batch.indexOf(entry.tab_id) >= 0)) return;
        const rest = root.capture_queue.map(batch => batch.filter(id => id !== entry.tab_id)).filter(batch => batch.length > 0);
        root.capture_queue = [[entry.tab_id]].concat(rest);
    }

    function captured(text) {
        const reply = FirefoxTabs.parse_reply(text);
        // A refused capture (sharing off, no Firefox) leaves the cards on their placeholders.
        if (reply.state !== "ok") {
            root.capture_queue = [];
            return;
        }
        root.thumbs = FirefoxTabs.merged_thumbs(root.thumbs, reply.fields.results);
    }

    function activate(item) {
        Quickshell.execDetached([root.firefox_tab, "focus", "tab:" + item.tab_id, item.label]);
    }

    function run_action(key, item) {
        if (key === "f") {
            root.filter = FirefoxTabs.cycled_filter(root.shown_filter, root.windows);
        } else if (key === "s") {
            FirefoxTabsSettings.set("sort", FirefoxTabs.cycled_sort(root.sort));
        } else if (key === "y") {
            Quickshell.execDetached(["wl-copy", "--", item.url]);
            root.copied = true;
            copied_timer.restart();
        } else if (key === "x" && root.host_state === "ok") {
            root.entries = root.entries.filter(e => e.id !== item.id);
            root.close_queue = root.close_queue.concat([item.tab_id]);
            root.close_next();
        }
    }

    function close_next() {
        if (close_proc.running) return;
        if (root.close_queue.length === 0) {
            // A refused close puts the tab back by listing again, but only once every queued close has answered:
            // an earlier list would still show a tab whose close was waiting, and nothing would remove it again.
            if (root.close_failed) {
                root.close_failed = false;
                list_proc.running = false;
                list_proc.command = root.request_argv({ verb: "tabs" });
                list_proc.running = true;
            }
            return;
        }
        close_proc.command = root.request_argv({ verb: "close", tab_id: root.close_queue[0] });
        root.close_queue = root.close_queue.slice(1);
        close_proc.running = true;
    }

    function closed(text) {
        if (FirefoxTabs.parse_reply(text).state !== "ok") root.close_failed = true;
    }

    onIs_shownChanged: if (root.is_shown) root.capture_next()

    Timer {
        id: copied_timer
        interval: 1500
        onTriggered: root.copied = false
    }

    Process {
        id: list_proc
        stdout: StdioCollector {
            onStreamFinished: root.listed(text)
        }
    }

    Process {
        id: capture_proc
        stdout: StdioCollector {
            onStreamFinished: root.captured(text)
        }
        onExited: capture_gap.restart()
    }

    // The bridge answers at most 10 requests a second over every verb, so batches never run back to back.
    Timer {
        id: capture_gap
        interval: 150
        onTriggered: root.capture_next()
    }

    Process {
        id: close_proc
        stdout: StdioCollector {
            onStreamFinished: root.closed(text)
        }
        onExited: Qt.callLater(root.close_next)
    }

    // The selected tab's image as large as fits, with its title and address under it; the setup hint with no tabs.
    preview: Component {
        Item {
            id: pane
            property var entry: null

            onEntryChanged: root.capture_first(pane.entry)

            TabThumbnail {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: caption_title.top
                anchors.margins: 8
                visible: !!pane.entry
                entry: pane.entry || ({})
                source: root.source_of(pane.entry)
                crop: false
                titled: true
            }

            Text {
                id: caption_title
                anchors.left: parent.left
                anchors.right: caption_tag.left
                anchors.bottom: caption_url.top
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                visible: !!pane.entry
                elide: Text.ElideRight
                text: pane.entry ? pane.entry.label : ""
                textFormat: Text.PlainText
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                font.bold: true
            }

            Text {
                id: caption_tag
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: caption_title.verticalCenter
                visible: !!pane.entry
                text: !pane.entry ? "" : [pane.entry.pinned ? "PINNED" : "", pane.entry.discarded ? "UNLOADED" : ""].filter(s => s !== "").join(" · ")
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
                font.bold: true
            }

            Text {
                id: caption_url
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                visible: !!pane.entry
                elide: Text.ElideMiddle
                text: pane.entry ? pane.entry.url : ""
                textFormat: Text.PlainText
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            Text {
                anchors.fill: parent
                anchors.margins: 16
                visible: !pane.entry && (root.host_state === "unavailable" || root.host_state === "sharing_off")
                text: root.host_state === "sharing_off" ? root.sharing_off_hint + ".\n\nIn DesertFox set bridge_share_tabs to true, then open the picker again." : "No Firefox tabs to show: Firefox is not running, or DesertFox's bridge is off.\n\nIn DesertFox set bridge and bridge_share_tabs to true. Private windows never show here: DesertFox does not share them."
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }
        }
    }

    // The tab's image across the top, then its favicon and title, then its short address.
    card: Component {
        Item {
            id: card
            property var entry: ({})
            property var positions: []
            property bool selected: false

            TabThumbnail {
                id: card_thumb
                width: parent.width
                height: parent.height - card_title.height - card_host.height - 10
                entry: card.entry
                source: root.source_of(card.entry)
            }

            WindowBadge {
                anchors.left: card_thumb.left
                anchors.top: card_thumb.top
                anchors.margins: Style.px(4)
                number: card.entry.window_number || 0
            }

            TabFavicon {
                id: card_icon
                anchors.verticalCenter: card_title.verticalCenter
                url: card.entry.fav_icon_url || ""
                size: Style.px(14)
            }

            Text {
                id: card_title
                anchors.top: card_thumb.bottom
                anchors.topMargin: 6
                anchors.left: card_icon.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: Fuzzy.highlight(card.entry.label || "", card.positions, String(Style.text_accent))
                color: card.entry.discarded ? Style.text_muted : Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
                font.bold: true
            }

            // Short of the card's foot corner, where the quick-pick number sits.
            Text {
                id: card_host
                anchors.top: card_title.bottom
                anchors.topMargin: 2
                width: parent.width - Style.px(16)
                elide: Text.ElideRight
                text: [card.entry.host || "", card.entry.discarded ? "unloaded" : ""].filter(s => s !== "").join(" · ")
                textFormat: Text.PlainText
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
            }
        }
    }

    // One line: a small image, the favicon and title, then the short address.
    row: Component {
        Item {
            id: line
            property var entry: ({})
            property var positions: []
            property bool selected: false

            TabThumbnail {
                id: line_thumb
                width: Math.round(line.height * 1.6)
                height: line.height
                entry: line.entry
                source: root.source_of(line.entry)
            }

            WindowBadge {
                id: line_badge
                anchors.left: line_thumb.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                number: line.entry.window_number || 0
            }

            TabFavicon {
                id: line_icon
                anchors.left: line_badge.visible ? line_badge.right : line_thumb.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                url: line.entry.fav_icon_url || ""
                size: Style.px(16)
            }

            Text {
                id: line_title
                anchors.left: line_icon.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(implicitWidth, parent.width - x - Style.px(200)))
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: Fuzzy.highlight(line.entry.label || "", line.positions, String(Style.text_accent))
                color: line.entry.discarded ? Style.text_muted : Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
            }

            Text {
                anchors.left: line_title.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: [line.entry.host || "", line.entry.discarded ? "unloaded" : ""].filter(s => s !== "").join(" · ")
                textFormat: Text.PlainText
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
            }
        }
    }

    // "W2": the tab's window in the recent sort, which mixes windows; the tab-order sort heads each window instead.
    component WindowBadge: Rectangle {
        id: badge
        property int number: 0

        visible: root.sort === "recent" && badge.number > 0
        width: badge_text.implicitWidth + 8
        height: badge_text.implicitHeight + 2
        radius: Style.radius(3)
        color: Qt.alpha(Theme.bg_surface, 0.9)
        border.width: 1
        border.color: Qt.alpha(Theme.ui_border, 0.8)

        Text {
            id: badge_text
            anchors.centerIn: parent
            text: "W" + badge.number
            color: Style.text_primary
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
            font.bold: true
        }
    }
}
