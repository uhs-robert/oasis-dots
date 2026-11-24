import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.theme
import "../../core/Fuzzy.js" as Fuzzy
import "VoxtypeHistory.js" as VoxtypeHistory

// voxtype's dictation history, newest first under a header per day: Enter types the entry into the window the picker
// opened over, `y` copies it, `x` deletes it from history and `f` brings back failed and cancelled ones.
PickerProvider {
    id: root

    name: "voxtype_history"
    start_group: "browse"
    layout: "browse"
    default_preview_size: "m"
    default_browse_view: "list"
    grouped: true
    title: "Dictation history"
    placeholder: "Search dictations"
    verb: "type"
    rank_by_usage: false
    keep_order: true
    actions: [{ key: "y", desc: "copy" }, { key: "x", desc: "delete" }, { key: "f", desc: "filter", needs_item: false }]
    empty_text: ({
        loading: "Loading dictations",
        missing: "voxtype is not installed",
        off: "History is off. Turn it on with: voxtype history enable",
        error: "Could not read voxtype history",
        ok: root.filter === "all" ? "No dictations yet" : "No delivered dictations. f shows failed ones"
    })[root.list_state]

    // "loading", then VoxtypeHistory.parse's state.
    property string list_state: "loading"
    property var entries: []
    // "delivered" or "all" (VoxtypeHistory.filters); every open starts at "delivered".
    property string filter: "delivered"
    items: root.entries.filter(e => VoxtypeHistory.kept_by_filter(e, root.filter))
    status_text: root.paused ? "PAUSED" : VoxtypeHistory.filter_labels[root.filter]
    status_active: root.paused || root.filter !== "delivered"
    property bool paused: false
    // Ids deleted this session. A list started before a delete lands still holds the entry, so this hides it.
    property var deleted: ({})
    // Set on each open, so the day headers do not shift while the picker is open past midnight.
    property date now: new Date()
    // Entry id `voxtype history paste` types once the picker's layer has gone, "" when none waits.
    property string paste_id: ""

    function refresh(arg) {
        root.filter = "delivered";
        root.now = new Date();
        if (list_proc.running) return;
        if (root.entries.length === 0) root.list_state = "loading";
        list_proc.running = true;
    }

    function listed(text) {
        const parsed = VoxtypeHistory.parse(text);
        root.list_state = parsed.state;
        root.paused = parsed.paused;
        root.entries = parsed.entries.filter(e => !root.deleted[e.id]);
    }

    function group_of(item) {
        return item.day;
    }

    function group_title(day, shown) {
        return VoxtypeHistory.group_title(day, shown.length, root.now);
    }

    // The picker has already closed, but its layer still holds the keyboard, so the paste waits for it to unmap.
    function activate(item) {
        root.paste_id = item.id;
        paste_fallback.restart();
    }

    function paste() {
        paste_fallback.stop();
        if (root.paste_id === "") return;
        Quickshell.execDetached(["voxtype", "history", "paste", root.paste_id]);
        root.paste_id = "";
    }

    function run_action(key, item) {
        if (key === "f") {
            root.filter = VoxtypeHistory.cycled_filter(root.filter);
        } else if (key === "y") {
            Pickers.close();
            Quickshell.execDetached(["voxtype", "history", "copy", item.id]);
        } else if (key === "x") {
            const d = Object.assign({}, root.deleted);
            d[item.id] = true;
            root.deleted = d;
            root.entries = root.entries.filter(e => e.id !== item.id);
            Quickshell.execDetached(["voxtype", "history", "delete", item.id]);
        }
    }

    Connections {
        target: Hyprland
        enabled: root.paste_id !== ""
        function onRawEvent(event) {
            if (event.name === "closelayer" && event.data === "quickshell-popup") root.paste();
        }
    }

    // In case closelayer never arrives, as Popups.after_close does.
    Timer {
        id: paste_fallback
        interval: 1000
        onTriggered: root.paste()
    }

    Process {
        id: list_proc
        // 5000 covers voxtype's default 30 days of history at about 150 dictations a day.
        command: ["sh", "-c", "command -v voxtype >/dev/null 2>&1 || { echo missing; exit 0; }; exec voxtype history list --json -n 5000"]
        stdout: StdioCollector {
            onStreamFinished: root.listed(text)
        }
    }

    // The whole dictation, then when and where it went.
    preview: Component {
        Item {
            id: pane
            property var entry: null
            clip: true

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: pane_meta.top
                anchors.margins: 10
                visible: !!pane.entry
                text: pane.entry ? pane.entry.text : ""
                textFormat: Text.PlainText
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                elide: Text.ElideRight
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }

            Text {
                id: pane_meta
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                visible: !!pane.entry
                elide: Text.ElideRight
                text: pane.entry ? [pane.entry.day, pane.entry.time, pane.entry.app, pane.entry.outcome].filter(s => s !== "").join(" · ") : ""
                textFormat: Text.PlainText
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }
    }

    // One line: the time, the dictation, then the app (and the outcome when it was not delivered).
    row: Component {
        Item {
            id: line
            property var entry: ({})
            property var positions: []
            property bool selected: false
            readonly property bool failed: !!line.entry.outcome && line.entry.outcome !== "delivered"

            Text {
                id: line_time
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: line.entry.time || ""
                textFormat: Text.PlainText
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            Text {
                id: line_text
                anchors.left: line_time.right
                anchors.leftMargin: 12
                anchors.right: line_where.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: Fuzzy.highlight(line.entry.label || "", line.positions, String(Style.text_accent))
                color: line.failed ? Style.text_muted : Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
            }

            Text {
                id: line_where
                anchors.right: parent.right
                anchors.rightMargin: Style.px(16)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Style.px(220))
                elide: Text.ElideRight
                text: [line.entry.app || "", line.failed ? line.entry.outcome : ""].filter(s => s !== "").join(" · ")
                textFormat: Text.PlainText
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
            }
        }
    }

    // The time and app, then the first lines of the dictation.
    card: Component {
        Item {
            id: card
            property var entry: ({})
            property var positions: []
            property bool selected: false

            Text {
                id: card_meta
                width: parent.width - Style.px(16)
                elide: Text.ElideRight
                text: [card.entry.time || "", card.entry.app || ""].filter(s => s !== "").join(" · ")
                textFormat: Text.PlainText
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
            }

            Text {
                anchors.top: card_meta.bottom
                anchors.topMargin: 4
                width: parent.width
                text: card.entry.text || ""
                textFormat: Text.PlainText
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 3
                elide: Text.ElideRight
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }
    }
}
