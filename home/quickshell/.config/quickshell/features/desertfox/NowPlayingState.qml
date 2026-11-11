pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "NowPlaying.js" as Playing

// The tab making sound in Firefox, from the DesertFox bridge host's event stream. One `subscribe` connection stays open
// while a now-playing module is mounted: the host allows four, so an unmounted bar holds no slot. The jump and the pause
// go out on short connections of their own, since a stream is one-way.
Singleton {
    id: root

    // Mounted DesertfoxPlaying modules (one per bar); the stream is open while any exist.
    property int mounted_modules: 0
    readonly property bool wanted: root.mounted_modules > 0

    property var playing: Playing.empty
    readonly property var tab: Playing.current(root.playing)
    readonly property bool shown: root.tab !== null
    // What a bar chip says; the full title is for the tooltip.
    readonly property string label: Playing.label_of(root.tab, 28)
    // "down" (no bridge answering), "refused" (all four subscriber places taken) or "streaming".
    property string link_state: "down"

    readonly property string socket_path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/desertfox/bridge.sock"
    // voxcmd's bridge client raises the Hyprland window by the title nonce (DesertFox assumes no window manager).
    readonly property string firefox_tab: Quickshell.env("HOME") + "/.local/share/voxcmd/firefox-tab"

    property int retry_ms: 1000

    function jump(): void {
        if (root.tab) Quickshell.execDetached([root.firefox_tab, "focus", "tab:" + root.tab.tab_id, root.tab.title]);
    }

    function pause(): void {
        if (root.tab) root.request(Playing.pause_request(root.tab.tab_id), null);
    }

    // One request on its own connection; `done` gets the reply line, or nothing is called when the bridge is gone.
    function request(message, done): void {
        request_component.createObject(root, { payload: JSON.stringify(message), done: done });
    }

    // A dropped or failed stream is retried after a growing wait. A refusal keeps the wait growing too, so a bar that
    // cannot get a place asks rarely, and only a granted stream resets it.
    function lost(refused: bool): void {
        root.link_state = refused ? "refused" : "down";
        root.playing = Playing.empty;
        link.active = false;
        if (!root.wanted) return;
        retry.interval = root.retry_ms;
        root.retry_ms = Playing.next_backoff_ms(root.retry_ms);
        retry.restart();
    }

    function on_line(text: string): void {
        const parsed = Playing.parse_line(text);
        if (parsed.kind === "event") {
            root.playing = Playing.reduce(root.playing, parsed.event);
        } else if (root.link_state !== "streaming") {
            if (parsed.kind === "ack") {
                root.link_state = "streaming";
                root.retry_ms = 1000;
                root.seed_from_tabs();
            } else if (parsed.kind === "refused") {
                root.lost(Playing.is_refusal(parsed));
            }
        }
    }

    // The stream says nothing of tabs that were already playing, so one tab list fills them in. With sharing off the
    // bridge refuses it and nothing is added, which is also right.
    function seed_from_tabs(): void {
        root.request({ verb: "tabs" }, text => {
            try {
                if (root.link_state === "streaming") root.playing = Playing.seed(root.playing, JSON.parse(text));
            } catch (e) {
            }
        });
    }

    onWantedChanged: {
        if (root.wanted) {
            root.retry_ms = 1000;
            link.active = true;
        } else {
            retry.stop();
            link.active = false;
            root.link_state = "down";
            root.playing = Playing.empty;
        }
    }

    Timer {
        id: retry
        onTriggered: {
            link.active = false;
            link.active = true;
        }
    }

    // A Socket never retries after a failed connect, so each attempt builds a fresh one (as MpvProcess does).
    Loader {
        id: link
        active: false
        sourceComponent: Socket {
            id: stream
            path: root.socket_path
            connected: true
            parser: SplitParser {
                onRead: line => root.on_line(line)
            }
            onConnectedChanged: {
                if (stream.connected) {
                    stream.write("{\"verb\":\"subscribe\"}\n");
                    stream.flush();
                } else if (link.item === stream) {
                    // A lost attempt empties the loader first, so a later close of the same socket lands here as a no-op.
                    root.lost(false);
                }
            }
            onError: if (link.item === stream) root.lost(false)
        }
    }

    Component {
        id: request_component

        Socket {
            id: call
            property string payload: ""
            property var done: null
            property bool sent: false
            path: root.socket_path
            connected: true
            parser: SplitParser {
                onRead: line => {
                    if (call.done) call.done(line);
                    call.done = null;
                    call.destroy();
                }
            }
            onConnectedChanged: {
                if (call.connected) {
                    call.write(call.payload + "\n");
                    call.flush();
                    call.sent = true;
                } else if (call.sent) {
                    call.destroy();
                }
            }
            onError: call.destroy()
        }
    }
}
