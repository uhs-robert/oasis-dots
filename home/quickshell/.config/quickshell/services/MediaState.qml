// home/quickshell/.config/quickshell/services/MediaState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

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
    }

    function previous() {
        if (root.active && root.active.canGoPrevious) root.active.previous();
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
        function onMetadataChanged() { root.remember_length(root.active); }
    }

    function seek_by(seconds) {
        if (!root.active || !root.active.canSeek || !root.active.positionSupported) return;
        const max = root.length_of(root.active) || Infinity;
        const target = Math.max(0, Math.min(max, root.active.position + seconds));
        root.active.position = target;
    }

    // MprisPlayer.position doesn't push updates on its own; poll it while a popup is open.
    Timer {
        interval: 1000
        running: root.tracking && !!root.active
        repeat: true
        onTriggered: if (root.active) root.active.positionChanged()
    }
}
