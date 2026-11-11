pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "NowPlaying.js" as Playing

// The tab making sound in Firefox, from the DesertFox bridge host's event stream. One `subscribe` connection stays open
// while a now-playing module is mounted: the host allows four, so an unmounted bar holds no slot. The jump and the pause
// go out on short connections of their own, since a stream is one-way.
Singleton {
    id: root

    // Mounted DesertfoxPlaying modules on a bar that can show them (one per horizontal bar); the stream is open while
    // any exist.
    property int mounted_modules: 0
    readonly property bool wanted: root.mounted_modules > 0

    property var playing: Playing.empty
    readonly property var tab: Playing.current(root.playing)
    // What a bar chip says; the full title is for the tooltip.
    readonly property string label: Playing.label_of(root.tab, 28)
    property bool streaming: false

    readonly property string socket_path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/desertfox/bridge.sock"
    // voxcmd's bridge client raises the Hyprland window by the title nonce (DesertFox assumes no window manager).
    readonly property string firefox_tab: Quickshell.env("HOME") + "/.local/share/voxcmd/firefox-tab"

    property int retry_ms: 1000
    // Which connection's tab list may still land. Every ack, loss, tabs_off and unmount moves it on, so a reply that was
    // in flight across one of them is dropped.
    property int generation: 0

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

    // A dropped or failed stream is retried after a growing wait, only on AC power: with Firefox closed the bridge stays
    // down and the retry would run for as long. A refusal grows the wait too, so a bar that cannot get a place asks
    // rarely, and only a granted stream resets it. An open stream is not touched by power.
    function lost(): void {
        root.streaming = false;
        root.generation++;
        root.playing = Playing.empty;
        link.active = false;
        if (!root.wanted || !PowerSource.on_ac) return;
        retry.interval = root.retry_ms;
        root.retry_ms = Playing.next_backoff_ms(root.retry_ms);
        retry.restart();
    }

    function on_line(text: string): void {
        const parsed = Playing.parse_line(text);
        if (parsed.kind === "event") {
            if (parsed.event.event === "tabs_off") root.generation++;
            root.playing = Playing.reduce(root.playing, parsed.event);
        } else if (!root.streaming) {
            if (parsed.kind === "ack") {
                root.streaming = true;
                root.generation++;
                root.retry_ms = 1000;
                root.seed_from_tabs();
            } else if (parsed.kind === "refused") {
                root.lost();
            }
        }
    }

    // The stream says nothing of tabs that were already playing, so one tab list fills them in. With sharing off the
    // bridge refuses it and nothing is added, which is also right.
    function seed_from_tabs(): void {
        const asked = root.generation;
        root.request({ verb: "tabs" }, text => {
            if (asked !== root.generation) return;
            try {
                root.playing = Playing.seed(root.playing, JSON.parse(text));
            } catch (e) {
            }
        });
    }

    onWantedChanged: {
        root.generation++;
        if (root.wanted) {
            root.retry_ms = 1000;
            link.active = true;
        } else {
            retry.stop();
            link.active = false;
            root.streaming = false;
            root.playing = Playing.empty;
        }
    }

    // Power came back while the stream was down and no retry waits: try again now.
    Connections {
        target: PowerSource
        function onOn_acChanged() {
            if (PowerSource.on_ac && root.wanted && !root.streaming && !retry.running && !link.active) link.active = true;
        }
    }

    Timer {
        id: retry
        onTriggered: {
            link.active = false;
            link.active = true;
        }
    }

    // A Socket that fails to connect reports neither an error nor a disconnect, so an attempt that is not connected a
    // second after it began counts as lost. Runs only while an attempt is open and not yet streaming.
    Timer {
        interval: 1000
        running: link.active && !root.streaming
        onTriggered: if (!link.item || !link.item.connected) root.lost()
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
                    root.lost();
                }
            }
            onError: if (link.item === stream) root.lost()
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
