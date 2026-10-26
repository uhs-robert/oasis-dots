pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "CavaViewers.js" as Viewers
import "PositionPoll.js" as PositionPoll

// Shared MPRIS state for the media bar module and popup. The active player is
// whichever one most recently started playing; ties broken by falling back to
// the first player, then null.
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    property var active: null
    property string selected_id: ""

    // Set by MediaPopup while open, so position keeps ticking only when it's visible.
    property bool tracking: false

    readonly property bool playing: !!root.active && root.active.isPlaying

    // dbusName -> ms timestamp the player last started playing.
    property var started_ms: ({})

    function player_id(p) {
        return p ? p.dbusName : "";
    }

    function find_by_id(id) {
        for (const p of root.players) {
            if (root.player_id(p) === id) return p;
        }
        return null;
    }

    function select(player) {
        root.selected_id = root.player_id(player);
        root.active = player;
    }

    // Picks the currently-playing player with the latest start time; if none are
    // playing, keeps the current selection when it still exists, else the first player.
    function recompute_active() {
        if (root.players.length === 0) {
            root.active = null;
            return;
        }

        const selected = root.find_by_id(root.selected_id);
        if (selected) {
            root.active = selected;
            return;
        }

        let best = null;
        let best_ms = -1;
        for (const p of root.players) {
            if (!p.isPlaying) continue;
            const ms = root.started_ms[root.player_id(p)] || 0;
            if (ms > best_ms) {
                best = p;
                best_ms = ms;
            }
        }

        if (best) {
            root.active = best;
        } else if (root.active && root.players.indexOf(root.active) !== -1) {
            // Keep the current active player through a pause.
        } else {
            root.active = root.players[0];
        }
    }

    onPlayersChanged: root.recompute_active()

    Instantiator {
        model: root.players

        delegate: Connections {
            id: watcher
            required property var modelData
            target: watcher.modelData

            function onIsPlayingChanged() {
                if (watcher.modelData.isPlaying) {
                    const map = Object.assign({}, root.started_ms);
                    map[root.player_id(watcher.modelData)] = Date.now();
                    root.started_ms = map;
                }
                root.recompute_active();
            }
        }
    }

    function toggle() {
        if (root.active && root.active.canTogglePlaying) root.active.togglePlaying();
    }

    function next() {
        if (root.active && root.active.canGoNext) root.active.next();
        Qt.callLater(root.refresh_position);
    }

    function previous() {
        if (root.active && root.active.canGoPrevious) root.active.previous();
        Qt.callLater(root.refresh_position);
    }

    // Firefox reports length only on some updates (e.g. after a pause or seek), so keep the last real one per track.
    property var known_lengths: ({})

    function track_key(player) {
        const meta = player.metadata || {};
        return meta["xesam:url"] || player.trackTitle || "";
    }

    function length_of(player) {
        if (!player) return 0;
        if (player.lengthSupported && player.length > 0) return player.length;
        return root.known_lengths[root.track_key(player)] || 0;
    }

    function remember_length(player) {
        if (!player || !player.lengthSupported || player.length <= 0) return;
        const key = root.track_key(player);
        if (!key || root.known_lengths[key] === player.length) return;
        const next = Object.assign({}, root.known_lengths);
        next[key] = player.length;
        root.known_lengths = next;
    }

    onActiveChanged: root.remember_length(root.active)

    Connections {
        target: root.active
        function onLengthChanged() { root.remember_length(root.active); }
        function onLengthSupportedChanged() { root.remember_length(root.active); }
        function onMetadataChanged() {
            root.remember_length(root.active);
            root.refresh_position();
        }
    }

    function seek_by(seconds) {
        if (!root.active || !root.active.canSeek || !root.active.positionSupported) return;
        const max = root.length_of(root.active) || Infinity;
        const target = Math.max(0, Math.min(max, root.active.position + seconds));
        root.active.position = target;
        Qt.callLater(root.refresh_position);
    }

    function step_player(delta) {
        if (root.players.length === 0) return;
        const idx = root.players.indexOf(root.active);
        const next_idx = (idx + delta + root.players.length) % root.players.length;
        root.select(root.players[next_idx]);
    }

    function seek_ratio(ratio) {
        if (!root.active || !root.active.canSeek || !root.active.positionSupported) return;
        const length = root.length_of(root.active);
        root.active.position = Math.max(0, Math.min(length, ratio * length));
        Qt.callLater(root.refresh_position);
    }

    function toggle_shuffle() {
        if (!root.active || !root.active.shuffleSupported) return;
        root.active.shuffle = !root.active.shuffle;
    }

    // Cycles None -> Playlist -> Track -> None.
    function cycle_loop() {
        if (!root.active || !root.active.loopSupported) return;
        const cur = root.active.loopState;
        if (cur === MprisLoopState.None) root.active.loopState = MprisLoopState.Playlist;
        else if (cur === MprisLoopState.Playlist) root.active.loopState = MprisLoopState.Track;
        else root.active.loopState = MprisLoopState.None;
    }

    // Whatever shows the position (a PositionViewer) registers here while it is visible.
    property var position_viewers: []
    function register_position(viewer) { root.position_viewers = Viewers.register(root.position_viewers, viewer); }
    function unregister_position(viewer) { root.position_viewers = Viewers.unregister(root.position_viewers, viewer); }

    // MprisPlayer.position doesn't push updates on its own; poll it only while something shows it (see PositionPoll.js).
    readonly property bool viewed: root.tracking || Viewers.any(root.position_viewers)
    readonly property int poll_ms: PositionPoll.interval(root.viewed, root.playing)
    readonly property bool polling: root.poll_ms > 0 && !!root.active
    function refresh_position() {
        if (root.viewed && root.active) root.active.positionChanged();
    }

    Timer {
        interval: root.poll_ms
        running: root.polling
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh_position()
    }

    // A paused view still needs a read when it appears, on a track change, and after our own seek or skip.
    onTrackingChanged: if (root.tracking && root.active) root.active.positionChanged()
    onPosition_viewersChanged: if (Viewers.any(root.position_viewers) && root.active) root.active.positionChanged()
}
