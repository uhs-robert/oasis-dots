import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.core
import qs.theme
import qs.features.popups
import qs.features.settings
import qs.features.windows
import "TmuxWindows.js" as TmuxWindows
import "AgentSessions.js" as AgentSessions
import "../../core/Fuzzy.js" as Fuzzy

// Every tmux window, under a header per session or most recently active first (`s`, remembered in TmuxSettings). The
// preview shows the chosen pane live; `[` and `]` choose another pane of the window, and Enter lands on it. `f` narrows
// the list to one session and `x` kills the window. The list reloads while it shows (TmuxWindows.kept_order).
PickerProvider {
    id: root

    name: "tmux"
    start_group: "browse"
    layout: "browse"
    default_preview_size: "m"
    default_browse_view: "list"
    card_size: Qt.size(300, 150)
    grouped: root.sort === "sessions"
    title: "Tmux windows"
    placeholder: "Search windows by session, name, command or path"
    verb: "go"
    rank_by_usage: false
    keep_order: true
    actions: [{ key: "x", desc: "kill window" }, { key: "[", desc: "previous pane" }, { key: "]", desc: "next pane" }, { key: "f", desc: "session", needs_item: false }, { key: "s", desc: "sort", needs_item: false }]
    empty_text: root.tmux_state === "loading" ? "Loading tmux windows" : root.tmux_state === "missing" ? "Tmux is not installed: install tmux to list its windows here" : root.tmux_state === "none" ? "No tmux server running: start tmux to list its windows here" : "No tmux windows"

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property int capture_interval_ms: 1000
    readonly property int card_tail_lines: 3

    // "loading", "ok", "missing" (no tmux binary) or "none" (no server, or no sessions).
    property string tmux_state: "loading"
    property var sessions: []
    property var clients: []
    // Every window in the order the rows show; `items` is the ones the session filter keeps.
    property var windows: []
    readonly property string sort: TmuxWindows.sort_of(TmuxSettings.sort)
    // "all" or a session id; every open starts at "all".
    property string filter: "all"
    readonly property string shown_filter: TmuxWindows.shown_filter(root.filter, root.sessions)
    items: root.windows.filter(w => TmuxWindows.kept_by_filter(w, root.shown_filter))
    // tmux window id -> true while its kill is queued or running, so a list read in the meantime does not bring it back.
    // A kill removes the window from every session it is linked into, so every row of it goes.
    property var killing: ({})
    property var kill_queue: []
    status_text: root.tmux_state === "ok" ? TmuxWindows.filter_label(root.shown_filter, root.sessions) + " · " + TmuxWindows.sort_labels[root.sort] : ""
    status_active: root.shown_filter !== "all"

    // row id -> the pane `[`/`]` chose; a row missing here shows its active pane. Every open starts empty.
    property var chosen_panes: ({})
    // pane id -> its last lines with text, for the cards.
    property var tails: ({})
    property string focus_address: ""
    readonly property string term_name: (DefaultAppsSettings.app_value("term") || Quickshell.env("TERMINAL") || "kitty").toLowerCase()

    function refresh(arg) {
        root.filter = "all";
        root.chosen_panes = {};
        // Cleared so the list that arrives is the picker's first, which selects initial_index.
        root.windows = [];
        root.tmux_state = "loading";
        root.list(true);
    }

    // `sorted` puts the rows in the sort's order (on open and after a kill); otherwise they keep their places.
    function list(sorted) {
        list_proc.running = false;
        list_proc.sorted = sorted;
        list_proc.command = TmuxWindows.list_argv();
        list_proc.running = true;
    }

    // The 1 s reload while the picker shows. It never cuts short a slow read, and waits out queued kills.
    function reload() {
        if (list_proc.running || root.kill_queue.length > 0 || kill_proc.running) return;
        root.list(false);
    }

    function listed(text, sorted) {
        const model = TmuxWindows.parse_list(text, root.home);
        const fresh = model.items.filter(w => !root.killing[w.window_id]);
        root.tmux_state = model.state;
        root.sessions = model.sessions;
        root.clients = model.clients;
        // A first list after the no-server hint is sorted, as on open.
        if (sorted || root.windows.length === 0) {
            // Set before the items: the picker reads it when they arrive.
            root.initial_index = TmuxWindows.initial_index(TmuxWindows.arranged(fresh, root.sort, root.shown_filter), model.clients);
            root.windows = TmuxWindows.arranged(fresh, root.sort, "all");
        } else {
            root.windows = TmuxWindows.kept_order(root.windows, fresh, root.sort);
        }
        // On battery the tails are captured only when the cards appear, not on every reload.
        if (root.shows_cards && PowerSource.on_ac) root.capture_tails();
    }

    onSortChanged: root.windows = TmuxWindows.arranged(root.windows, root.sort, "all")
    onShows_cardsChanged: if (root.shows_cards) root.capture_tails()

    function group_of(item) {
        return item.session_id;
    }

    function group_title(session_id, shown) {
        return TmuxWindows.group_title(session_id, shown.length, root.sessions);
    }

    function shown_pane(item) {
        return TmuxWindows.pane_of(item, item ? root.chosen_panes[item.id] : "");
    }

    function run_action(key, item) {
        if (key === "f") {
            root.filter = TmuxWindows.cycled_filter(root.shown_filter, root.sessions);
        } else if (key === "s") {
            TmuxSettings.set("sort", TmuxWindows.cycled_sort(root.sort));
        } else if (key === "[" || key === "]") {
            const pane = root.shown_pane(item);
            const next = Object.assign({}, root.chosen_panes);
            next[item.id] = TmuxWindows.cycled_pane(item, pane ? pane.pane_id : "", key === "]" ? 1 : -1);
            root.chosen_panes = next;
        } else if (key === "x") {
            root.windows = root.windows.filter(w => w.window_id !== item.window_id);
            // A session filter with no windows left would show "No tmux windows" until the list returns.
            if (!root.windows.some(w => TmuxWindows.kept_by_filter(w, root.shown_filter))) root.filter = "all";
            const killing = Object.assign({}, root.killing);
            killing[item.window_id] = true;
            root.killing = killing;
            root.kill_queue = root.kill_queue.concat([item.window_id]);
            root.kill_next();
        }
    }

    // One kill at a time, then one sorted list once the queue is empty, so it shows what tmux did (a refused kill
    // brings its window back).
    function kill_next() {
        if (kill_proc.running) return;
        if (root.kill_queue.length === 0) {
            root.killing = {};
            root.list(true);
            return;
        }
        kill_proc.command = ["tmux", "kill-window", "-t", root.kill_queue[0]];
        root.kill_queue = root.kill_queue.slice(1);
        kill_proc.running = true;
    }

    function capture_tails() {
        if (tails_proc.running || root.windows.length === 0) return;
        tails_proc.command = TmuxWindows.tails_argv(root.windows.map(w => w.active_pane).filter(id => id !== ""));
        tails_proc.running = true;
    }

    // The terminal window whose title names the session, among the configured terminal's windows.
    function window_address(session_name) {
        const names = root.sessions.map(s => s.name);
        const found = WindowState.windows.find(w => (WindowState.class_of(w) || "").toLowerCase().indexOf(root.term_name) >= 0 && TmuxWindows.title_matches(w.title || "", session_name, names));
        return found ? found.address : "";
    }

    function session_name_of(session_id) {
        const session = root.sessions.find(s => s.id === session_id);
        return session ? session.name : "";
    }

    // A client already showing the session selects the window and pane there; else the latest client switches to it;
    // else a new terminal attaches to the session.
    function activate(item) {
        const pane = root.shown_pane(item);
        // The row id `$session:@window`, not the bare window id: a linked window is selected in this row's session.
        const select = ["select-window", "-t", item.id].concat(pane ? [";", "select-pane", "-t", pane.pane_id] : []);
        let address = TmuxWindows.client_of(root.clients, item.session_id) ? root.window_address(item.session_name) : "";
        if (address !== "") {
            Quickshell.execDetached(["tmux"].concat(select));
        } else {
            const latest = TmuxWindows.latest_client(root.clients);
            if (latest) {
                address = root.window_address(root.session_name_of(latest.session_id));
                Quickshell.execDetached(["tmux", "switch-client", "-c", latest.name, "-t", item.session_id, ";"].concat(select));
            } else {
                Quickshell.execDetached(["tmux"].concat(select));
                root.launch_argv = ["sh", "-c", "t=\"$0\"; [ -x \"$t\" ] || t=\"${TERMINAL:-kitty}\"; exec \"$t\" -e tmux attach-session -t \"$1\"", Paths.term_script, item.session_id];
                layer_fallback.restart();
                return;
            }
        }
        if (address === "") return;
        WindowState.focus(address);
        root.focus_address = address;
        layer_fallback.restart();
    }

    // What waits for the picker's layer to unmap, as Popups.after_close waits for a popup's. Picker closes the popup
    // before it calls activate, so after_close itself runs at once. A terminal launched or focused while the
    // layer holds the keyboard is left unfocused; an existing one is also focused once at Enter, as WindowsProvider does.
    property var launch_argv: null

    function layer_closed() {
        layer_fallback.stop();
        const argv = root.launch_argv;
        const address = root.focus_address;
        root.launch_argv = null;
        root.focus_address = "";
        // A popup opened since the picker closed keeps the keyboard.
        if (Popups.open_name !== "") return;
        if (argv) Quickshell.execDetached(argv);
        if (address !== "") WindowState.focus(address);
    }

    Connections {
        target: Hyprland
        enabled: root.focus_address !== "" || root.launch_argv !== null
        function onRawEvent(event) {
            if (event.name === "closelayer" && event.data === "quickshell-popup") root.layer_closed();
        }
    }

    // In case closelayer never arrives, as Popups.after_close does.
    Timer {
        id: layer_fallback
        interval: 1000
        onTriggered: root.layer_closed()
    }

    // The list reloads on battery too, only less often: a stale list sends Enter to windows that are gone, and one read
    // is a single tmux call. It keeps reloading with no server, so a session started meanwhile replaces the hint.
    Timer {
        interval: PowerSource.on_ac ? root.capture_interval_ms : 3 * root.capture_interval_ms
        repeat: true
        running: root.is_shown && (root.tmux_state === "ok" || root.tmux_state === "none")
        onTriggered: root.reload()
    }

    // Every card's tail in one plain capture while the cards show; on battery only each time the cards appear.
    Timer {
        interval: root.capture_interval_ms
        repeat: true
        running: root.shows_cards && root.tmux_state === "ok" && PowerSource.on_ac
        onTriggered: root.capture_tails()
    }

    Process {
        id: list_proc
        property bool sorted: true
        stdout: StdioCollector {
            onStreamFinished: root.listed(text, list_proc.sorted)
        }
    }

    Process {
        id: tails_proc
        stdout: StdioCollector {
            onStreamFinished: root.tails = TmuxWindows.parse_tails(text, root.card_tail_lines)
        }
    }

    Process {
        id: kill_proc
        onExited: Qt.callLater(root.kill_next)
    }

    // The chosen pane's text, live on AC, with its place and command in the corner.
    preview: Component {
        Item {
            id: pane
            property var entry: null
            readonly property var shown: root.shown_pane(pane.entry)
            readonly property string pane_id: pane.shown ? pane.shown.pane_id : ""
            // Pane the shown text was captured from, so a late capture never lands on another pane.
            property string text_id: ""
            property string pane_text: ""
            property int pane_columns: 0
            property bool failed: false

            clip: true

            // A new pane starts blank. A capture still running finishes, is dropped as another pane's, and `settle`
            // starts the new one.
            onPane_idChanged: {
                pane.pane_text = "";
                pane.text_id = "";
                pane.failed = false;
                Qt.callLater(pane.capture);
            }

            function capture() {
                if (pane.pane_id === "" || capture_proc.running) return;
                capture_proc.target_id = pane.pane_id;
                capture_proc.pending_text = null;
                capture_proc.pending_code = null;
                capture_proc.command = TmuxWindows.capture_argv(pane.pane_id);
                capture_proc.running = true;
            }

            function captured(id, text, code) {
                if (pane.pane_id !== id) return;
                pane.failed = code !== 0;
                if (code !== 0) return;
                const capture = AgentSessions.split_capture(text);
                pane.text_id = id;
                pane.pane_columns = capture.width;
                pane.pane_text = capture.text;
            }

            Timer {
                interval: root.capture_interval_ms
                repeat: true
                running: pane.pane_id !== "" && root.is_shown && PowerSource.on_ac
                onTriggered: pane.capture()
            }

            Process {
                id: capture_proc
                property string target_id: ""
                property var pending_text: null
                property var pending_code: null

                // The collector can finish after the exit signal, so the capture counts once both are in (or the
                // process failed, when there may be no output at all).
                function settle() {
                    if (capture_proc.pending_code === null) return;
                    if (capture_proc.pending_text === null && capture_proc.pending_code === 0) return;
                    const id = capture_proc.target_id;
                    pane.captured(id, capture_proc.pending_text || "", capture_proc.pending_code);
                    capture_proc.pending_text = null;
                    capture_proc.pending_code = null;
                    if (pane.pane_id !== "" && pane.pane_id !== id) Qt.callLater(pane.capture);
                }

                stdout: StdioCollector {
                    onStreamFinished: {
                        capture_proc.pending_text = text;
                        capture_proc.settle();
                    }
                }
                onExited: code => {
                    capture_proc.pending_code = code;
                    capture_proc.settle();
                }
            }

            Text {
                anchors.fill: parent
                anchors.margins: 10
                visible: !!pane.entry && pane.failed
                text: "No preview: the pane is gone."
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            AnsiPane {
                anchors.fill: parent
                visible: !pane.failed && pane.text_id !== ""
                pane_text: pane.pane_text
                pane_columns: pane.pane_columns
            }

            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 6
                visible: corner_text.text !== ""
                width: corner_text.implicitWidth + 12
                height: corner_text.implicitHeight + 4
                radius: Style.radius(3)
                color: Qt.alpha(Theme.bg_surface, 0.9)
                border.width: 1
                border.color: Qt.alpha(Theme.ui_border, 0.8)

                Text {
                    id: corner_text
                    anchors.centerIn: parent
                    text: TmuxWindows.pane_label(pane.entry, pane.shown)
                    textFormat: Text.PlainText
                    color: Style.text_primary
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                    font.bold: true
                }
            }
        }
    }

    // The window's name and session, its pane count, its active pane's command and path, then that pane's last lines.
    card: Component {
        Item {
            id: card
            property var entry: ({})
            property var positions: []
            property bool selected: false

            Text {
                id: card_title
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: (card.entry.index !== undefined ? card.entry.index + "&nbsp;&nbsp;" : "") + Fuzzy.highlight(card.entry.label || "", card.positions, String(Style.text_accent))
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                font.bold: true
            }

            Text {
                id: card_session
                anchors.top: card_title.bottom
                anchors.topMargin: 4
                width: parent.width
                elide: Text.ElideRight
                text: [card.entry.session_name || "", (card.entry.panes || []).length + ((card.entry.panes || []).length === 1 ? " pane" : " panes")].join(" · ")
                textFormat: Text.PlainText
                color: Style.text_primary
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            Text {
                id: card_where
                anchors.top: card_session.bottom
                anchors.topMargin: 3
                width: parent.width
                elide: Text.ElideMiddle
                text: [card.entry.cmd || "", card.entry.short_path || ""].filter(s => s !== "").join(" · ")
                textFormat: Text.PlainText
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            // Short of the card's foot corner, where the quick-pick number sits.
            Text {
                anchors.top: card_where.bottom
                anchors.topMargin: 4
                anchors.bottom: parent.bottom
                width: parent.width - Style.px(16)
                clip: true
                text: root.tails[card.entry.active_pane] || ""
                textFormat: Text.PlainText
                color: Style.text_dim
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-4)
            }
        }
    }

    // One line: the window's index and name, its session in the recent sort, then the active pane's command and path.
    row: Component {
        Item {
            id: line
            property var entry: ({})
            property var positions: []
            property bool selected: false

            Text {
                id: line_icon
                anchors.verticalCenter: parent.verticalCenter
                width: Style.px(20)
                horizontalAlignment: Text.AlignHCenter
                text: "\u{ebc8}"
                color: Style.text_muted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.fs(0)
            }

            Text {
                id: line_index
                anchors.left: line_icon.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: line.entry.index !== undefined ? String(line.entry.index) : ""
                color: Style.text_primary
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-2)
                font.bold: true
            }

            Text {
                id: line_title
                anchors.left: line_index.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(implicitWidth, parent.width * 0.35))
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: Fuzzy.highlight(line.entry.label || "", line.positions, String(Style.text_accent))
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
                font.bold: true
            }

            SessionBadge {
                id: line_badge
                anchors.left: line_title.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                name: line.entry.session_name || ""
            }

            Text {
                anchors.left: line_badge.visible ? line_badge.right : line_title.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideMiddle
                text: [line.entry.cmd || "", line.entry.short_path || ""].filter(s => s !== "").join(" · ")
                textFormat: Text.PlainText
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
            }
        }
    }

    // The window's session in the recent sort, which mixes sessions; the session sort heads each session instead.
    component SessionBadge: Rectangle {
        id: badge
        property string name: ""

        visible: root.sort === "recent" && badge.name !== ""
        width: Math.min(badge_text.implicitWidth, Style.px(160)) + 8
        height: badge_text.implicitHeight + 2
        radius: Style.radius(3)
        color: Qt.alpha(Theme.bg_surface, 0.9)
        border.width: 1
        border.color: Qt.alpha(Theme.ui_border, 0.8)

        Text {
            id: badge_text
            anchors.centerIn: parent
            width: Math.min(implicitWidth, Style.px(160))
            elide: Text.ElideRight
            text: badge.name
            textFormat: Text.PlainText
            color: Style.text_primary
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
            font.bold: true
        }
    }
}
