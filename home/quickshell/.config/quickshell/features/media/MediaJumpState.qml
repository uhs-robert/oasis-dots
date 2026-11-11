pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "MediaJump.js" as MediaJump
import "../launcher/FirefoxTabs.js" as FirefoxTabs

// Jumps from the media module to the Firefox tab playing its track: one `tabs` request through DesertFox's bridge at
// jump time (no subscription), then `firefox-tab focus`. When the bridge is down or tab sharing is off it raises the
// Firefox window only and says why once.
Singleton {
    id: root

    readonly property string firefox_tab: Quickshell.env("HOME") + "/.local/share/voxcmd/firefox-tab"

    readonly property var player: MediaState.active
    readonly property bool player_is_firefox: !!root.player && MediaJump.is_firefox_player(root.player.desktopEntry, root.player.dbusName)

    // Which causes already got their notice this session.
    property var noticed: ({})

    // Starts the jump and returns how far the synchronous part got: "no player", "not firefox" or "jumping".
    function jump() {
        if (!root.player) return "no player";
        if (!root.player_is_firefox) {
            root.say("The active player is not Firefox");
            return "not firefox";
        }
        root.target_title = root.player.trackTitle || "";
        const meta = root.player.metadata;
        root.target_url = meta && meta["xesam:url"] ? String(meta["xesam:url"]) : "";
        root.target_playing = root.player.isPlaying;
        tabs_proc.running = false;
        tabs_proc.running = true;
        return "jumping";
    }

    property string target_title: ""
    property string target_url: ""
    property bool target_playing: false

    // For a miss the user just caused: every press answers.
    function say(text) {
        Quickshell.execDetached(["notify-send", "-a", "Media", text]);
    }

    // For a standing condition (sharing off, bridge down): once per session per cause.
    function notice(cause, text) {
        if (root.noticed[cause]) return;
        root.noticed[cause] = true;
        root.say(text);
    }

    function on_tabs(text) {
        const reply = FirefoxTabs.parse_reply(text);
        if (reply.state === "ok") {
            const tab = MediaJump.pick_tab(reply.fields.tabs, root.target_title, root.target_url, root.target_playing);
            if (!tab) {
                root.raise_window();
                return;
            }
            Quickshell.execDetached([root.firefox_tab, "focus", "tab:" + tab.tab_id, String(tab.title || tab.url || "")]);
            return;
        }
        root.raise_window();
        if (reply.state === "sharing_off") root.notice("sharing_off", "DesertFox is not sharing its tabs: set bridge_share_tabs to true. Raised the Firefox window only");
        else if (reply.state === "unavailable") root.notice("unavailable", "The DesertFox bridge is not reachable. Raised the Firefox window only");
        else if (reply.state === "error") root.notice("error", "Firefox did not list its tabs: " + reply.error);
    }

    // The most recently focused Firefox window, whichever tab it shows. A window never focused (focusHistoryID -1) is skipped.
    function raise_window() {
        Quickshell.execDetached(["sh", "-c", raise_script]);
    }

    readonly property string raise_script: `
command -v hyprctl >/dev/null && command -v jq >/dev/null || exit 0
addr=$(hyprctl -j clients | jq -r '[.[] | select((.class | ascii_downcase) | test("^(firefox|org\\\\.mozilla\\\\.firefox)") and .focusHistoryID >= 0)] | sort_by(.focusHistoryID) | .[0].address // empty')
[ -n "$addr" ] && hyprctl dispatch "hl.dsp.focus({ window = 'address:$addr' })"
exit 0
`

    // Through `sh -c` so a missing firefox-tab is an empty answer, which parse_reply reads as unavailable.
    Process {
        id: tabs_proc
        command: ["sh", "-c", "exec \"$0\" request \"$1\"", root.firefox_tab, JSON.stringify({ verb: "tabs" })]
        stdout: StdioCollector {
            onStreamFinished: root.on_tabs(text)
        }
    }
}
