import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme
import "AgentSessions.js" as AgentSessions
import "AnsiText.js" as AnsiText

// Running agent sessions from keeptabs, in its own order: Enter jumps to the session's window, and the preview shows
// the session's tmux pane as text, refreshed while its row is selected.
PickerProvider {
    id: root

    name: "agents"
    start_group: "browse"
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

    function refresh(arg) {
        list_proc.running = false;
        list_proc.running = true;
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
            readonly property bool has_pane: !!pane.entry && pane.entry.tmux_pane !== ""
            // Id of the entry the shown text was captured for, so a late capture never lands on another row.
            property string text_id: ""
            property string styled: ""
            property bool failed: false
            readonly property int max_lines: Math.max(1, Math.floor((pane.height - 20) / metrics.height))

            clip: true

            // A new row starts blank, so the previous row's text never shows under it. A capture still running is not
            // killed (its exit would be read as the new row's); it finishes, is dropped as another row's, and `settle` starts the new one.
            onEntryChanged: {
                pane.styled = "";
                pane.text_id = "";
                pane.failed = false;
                if (pane.has_pane) pane.capture();
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
                pane.text_id = id;
                pane.styled = AnsiText.to_styled(AnsiText.bottom_lines(text, pane.max_lines), String(Style.text_fg));
            }

            FontMetrics {
                id: metrics
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-3)
            }

            Timer {
                interval: root.capture_interval_ms
                repeat: true
                running: pane.has_pane
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

            Rectangle {
                anchors.fill: parent
                radius: Style.radius(4)
                color: Style.pal.bg_surface
            }

            Text {
                anchors.fill: parent
                anchors.margins: 10
                visible: !pane.has_pane || pane.failed || pane.text_id === ""
                text: !pane.entry ? "" : !pane.has_pane ? "No preview: this session is not in a tmux pane." : pane.failed ? "No preview: the tmux pane is gone." : ""
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                visible: pane.has_pane && !pane.failed && pane.text_id !== ""
                text: pane.styled
                textFormat: Text.StyledText
                wrapMode: Text.NoWrap
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-3)
            }
        }
    }
}
