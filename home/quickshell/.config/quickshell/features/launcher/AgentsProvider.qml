import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.theme
import qs.features.keeptabs
import qs.features.keeptabs.views
import "AgentSessions.js" as AgentSessions
import "../../core/Fuzzy.js" as Fuzzy

// Running agent sessions from keeptabs, in its own order: Enter jumps to the session's window, the preview shows the
// selected session's tmux pane or kitty window as text (Tab swaps in Claude usage, as the keeptabs popup's Usage tab
// shows it), and each card its state, how full its context is and the last line its pane printed, refreshed while open.
PickerProvider {
    id: root

    name: "agents"
    start_group: "browse"
    layout: "browse"
    default_preview_size: "l"
    card_size: Qt.size(300, 112)
    title: "Agent sessions"
    placeholder: "Search agent sessions"
    verb: "jump"
    rank_by_usage: false
    keep_order: true
    empty_text: "No agent sessions running"

    readonly property string home: Quickshell.env("HOME")
    // keeptabs lives outside this repo; it also does the jumping (tmux, kitty, Hyprland), so it is called, not copied.
    readonly property string keeptabs_pick: root.home + "/.local/bin/keeptabs-pick"
    readonly property int capture_interval_ms: 1000
    // id -> the last line with words in that session's pane, for the cards.
    property var tails: ({})
    // Set by a battery list read that lands while a capture runs: that capture's tails are for the old list, so a new one
    // starts once it ends.
    property bool tails_pending: false

    function refresh(arg) {
        list_proc.running = false;
        list_proc.running = true;
    }

    function capture_tails() {
        if (tails_proc.running || root.items.length === 0) return;
        root.tails_pending = false;
        tails_proc.command = AgentSessions.tails_argv(root.items);
        tails_proc.running = true;
    }

    // Every pane at once, in one light plain capture, so the cards stay live without a process per card. On battery the
    // cards get one capture per list read instead.
    Timer {
        interval: root.capture_interval_ms
        repeat: true
        triggeredOnStart: true
        running: root.is_shown && root.items.length > 0 && PowerSource.on_ac
        onTriggered: root.capture_tails()
    }

    onItemsChanged: {
        if (!root.is_shown || PowerSource.on_ac) return;
        root.tails_pending = true;
        root.capture_tails();
    }

    // Retried from both ends of a run, since the collector can finish before or after the exit; capture_tails starts it
    // only once the process is no longer running.
    function capture_pending_tails() {
        if (root.tails_pending) Qt.callLater(root.capture_tails);
    }

    Process {
        id: tails_proc
        onRunningChanged: if (!tails_proc.running) root.capture_pending_tails()
        stdout: StdioCollector {
            onStreamFinished: {
                root.tails = AgentSessions.parse_tails(text);
                root.capture_pending_tails();
            }
        }
    }

    function activate(item) {
        Quickshell.execDetached([root.keeptabs_pick, "--focus", item.id]);
    }

    Process {
        id: list_proc
        command: [root.keeptabs_pick, "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.items = AgentSessions.parse_sessions(text, root.home)
        }
    }

    preview: Component {
        Item {
            id: pane
            property var entry: null
            readonly property bool has_pane: !!pane.entry && (pane.entry.tmux_pane !== "" || pane.entry.pid !== "")
            // Id of the entry the shown text was captured for, so a late capture never lands on another row.
            property string text_id: ""
            property string pane_text: ""
            // The pane's width in columns, from the capture; 0 until one lands.
            property int pane_columns: 0
            property bool failed: false

            clip: true

            // A new row starts blank, so the previous row's text never shows under it. A capture still running is not
            // killed (its exit would be read as the new row's); it finishes, is dropped as another row's, and `settle` starts the new one.
            onEntryChanged: {
                pane.pane_text = "";
                pane.text_id = "";
                pane.failed = false;
                // Deferred, and capture() checks has_pane itself: a reloaded preview (Tab back, p) gets its entry while it is
                // still being built, when has_pane has not caught up yet and reads false.
                Qt.callLater(pane.capture);
            }

            function capture() {
                if (!pane.has_pane || capture_proc.running) return;
                capture_proc.target_id = pane.entry.id;
                capture_proc.pending_text = null;
                capture_proc.pending_code = null;
                capture_proc.command = AgentSessions.capture_argv(pane.entry);
                capture_proc.running = true;
            }

            function captured(id, text, code) {
                if (!pane.entry || pane.entry.id !== id) return;
                pane.failed = code !== 0;
                if (code !== 0) return;
                const capture = AgentSessions.split_capture(text);
                pane.text_id = id;
                pane.pane_columns = capture.width;
                pane.pane_text = capture.text;
            }

            // On battery the text is captured only when the selected row changes.
            Timer {
                interval: root.capture_interval_ms
                repeat: true
                running: pane.has_pane && PowerSource.on_ac
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
                    if (pane.has_pane && pane.entry.id !== id) Qt.callLater(pane.capture);
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
                visible: !pane.has_pane || pane.failed || pane.text_id === ""
                text: !pane.entry ? "" : !pane.has_pane ? "No preview: keeptabs knows no tmux pane or process for this session." : !pane.failed ? "" : pane.entry.tmux_pane !== "" ? "No preview: the tmux pane is gone." : "No preview: this session is not in tmux or in a kitty window with remote control (allow_remote_control and listen_on)."
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            AnsiPane {
                anchors.fill: parent
                visible: pane.has_pane && !pane.failed && pane.text_id !== ""
                pane_text: pane.pane_text
                pane_columns: pane.pane_columns
            }
        }
    }

    alt_preview_name: "usage"
    // The keeptabs popup's generic Usage view, not the style's own layout: those are drawn for the popup's frame.
    alt_preview: Component {
        Item {
            Component.onCompleted: ClaudeUsageState.refresh(false)

            UsageView {
                anchors.fill: parent
                anchors.margins: 10
            }
        }
    }

    card: Component {
        Item {
            id: card
            property var entry: ({})
            property var positions: []
            property bool selected: false

            Text {
                id: title
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: Fuzzy.highlight(card.entry.label || "", card.positions, String(Style.text_accent))
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                font.bold: true
            }

            AgentStateBadge {
                id: badge
                anchors.top: title.bottom
                anchors.topMargin: 5
                run_state: card.entry.state || ""
            }

            // On the badge's line, not the card's foot, where the quick-pick number sits.
            AgentContextBar {
                id: card_context
                anchors.right: parent.right
                anchors.verticalCenter: badge.verticalCenter
                context: card.entry.context || null
            }

            Text {
                anchors.left: badge.visible ? badge.right : parent.left
                anchors.leftMargin: badge.visible ? 8 : 0
                anchors.right: card_context.visible ? card_context.left : parent.right
                anchors.rightMargin: card_context.visible ? 8 : 0
                anchors.verticalCenter: badge.verticalCenter
                elide: Text.ElideRight
                text: card.entry.agent || ""
                textFormat: Text.PlainText
                color: Style.text_primary
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            Text {
                id: cwd
                anchors.top: badge.bottom
                anchors.topMargin: 5
                width: parent.width
                elide: Text.ElideMiddle
                text: card.entry.cwd_short || ""
                textFormat: Text.PlainText
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            Text {
                anchors.top: cwd.bottom
                anchors.topMargin: 3
                width: parent.width
                elide: Text.ElideRight
                text: root.tails[card.entry.id] || ""
                textFormat: Text.PlainText
                color: Style.text_dim
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-4)
            }
        }
    }

    // One line: title, state, agent and short directory, the context bar at the end, then the pane's last line in what is left.
    row: Component {
        Item {
            id: line
            property var entry: ({})
            property var positions: []
            property bool selected: false
            // Where the title and directory must stop, so a long one elides before the context bar instead of under it.
            readonly property real text_end: line_context.visible ? line_context.x - 14 : width
            readonly property real badge_room: line_badge.visible ? line_badge.width + 10 : 0

            Text {
                id: line_icon
                anchors.verticalCenter: parent.verticalCenter
                width: Style.px(20)
                horizontalAlignment: Text.AlignHCenter
                text: "\u{f489}"
                color: Style.text_muted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.fs(0)
            }

            Text {
                id: line_title
                anchors.left: line_icon.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(implicitWidth, parent.width * 0.3, line.text_end - x - line.badge_room - 10))
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: Fuzzy.highlight(line.entry.label || "", line.positions, String(Style.text_accent))
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                font.bold: true
            }

            AgentStateBadge {
                id: line_badge
                anchors.left: line_title.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                run_state: line.entry.state || ""
            }

            Text {
                id: line_where
                anchors.left: line_badge.visible ? line_badge.right : line_title.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(implicitWidth, parent.width * 0.3, line.text_end - x))
                elide: Text.ElideMiddle
                text: [line.entry.agent || "", line.entry.cwd_short || ""].filter(s => s !== "").join(" · ")
                textFormat: Text.PlainText
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            AgentContextBar {
                id: line_context
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                context: line.entry.context || null
            }

            Text {
                anchors.left: line_where.right
                anchors.leftMargin: 14
                anchors.right: line_context.visible ? line_context.left : parent.right
                anchors.rightMargin: line_context.visible ? 14 : 0
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.tails[line.entry.id] || ""
                textFormat: Text.PlainText
                color: Style.text_dim
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-4)
            }
        }
    }
}
