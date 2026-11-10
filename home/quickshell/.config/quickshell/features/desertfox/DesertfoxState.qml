pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.features.voice
import qs.features.windows
import "DesertfoxState.js" as State

// The DesertFox mode and which-key panel, read from the snapshot the DesertFox display host keeps at
// $XDG_RUNTIME_DIR/desertfox/state.json. Both only show while Firefox is the focused window; the file itself says
// nothing about focus when Firefox loses it.
Singleton {
    id: root

    // The file belongs to a running host of a known version.
    readonly property bool live: store.values.valid && root.owner_alive && root.probed_owner === root.owner_key
    // By address, not Hyprland.activeToplevel: that stays null after a Quickshell restart until the first focus event.
    readonly property bool firefox_focused: State.is_firefox_class(WindowState.class_of(WindowState.windows.find(t => t.address === WindowState.active_address)))
    readonly property bool shown: root.live && root.firefox_focused

    readonly property string mode_id: store.values.mode_id
    // Empty hides the chip: hint and cmdline draw their own surface.
    readonly property string chip_label: root.shown ? store.values.mode_label : ""
    readonly property bool has_panel: root.shown && store.values.whichkey_items.length > 0
    readonly property string panel_key: State.panel_key(store.values)
    readonly property var panel_payload: State.payload_of(store.values)

    readonly property string state_dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/desertfox"
    readonly property int owner: store.values.host_pid
    readonly property string owner_start: store.values.host_start
    readonly property string owner_key: root.owner + ":" + root.owner_start
    property bool owner_alive: false
    // The owner the last probe judged, so a new host's file is not shown on the strength of the old host's probe.
    property string probed_owner: ""
    property bool state_dir_exists: false

    // A missing, half-written or unknown file is the defaults: nothing shows. The host replaces the file by rename and
    // JsonStore rereads on the change.
    JsonStore {
        id: store
        path: root.state_dir + "/state.json"
        read_only: true
        defaults: State.empty
        validate: State.validate
        onLoaded: {
            if (store.values.valid) owner_probe.poll();
        }
    }

    // Like VoxSessionState's wait for voxcmd's folder, but kept up: the host makes its folder on first use and a watch
    // armed before that never fires for the file, and a folder that goes and comes back loses the watch the same way.
    // Reading a folder fails with an error other than FileNotFound; FileNotFound is the folder being gone.
    PolledFile {
        id: state_dir_probe
        path: root.state_dir
        interval_ms: 1000
        block_loading: true
        onLoad_failed: error => {
            const gone = error === FileViewError.FileNotFound;
            if (gone === !root.state_dir_exists)
                return;
            root.state_dir_exists = !gone;
            if (!gone)
                store.rearm();
        }
    }

    // The host deletes the file when it ends, except when it is killed outright, so while a file shows, its host is
    // checked: the pid with the start time the host saved, since a bare pid could be a process that reused it.
    PolledFile {
        id: owner_probe
        path: root.owner > 0 ? "/proc/" + root.owner + "/stat" : ""
        // A host found dead stays dead until the file changes (onLoaded of the store polls once then).
        enabled: store.values.valid && !(root.probed_owner === root.owner_key && !root.owner_alive)
        interval_ms: 3000
        run_on_start: false
        block_loading: true
        onLoaded: text => root.judge_owner(root.owner_start !== "" && VoxSessionState.process_start_time(text) === root.owner_start)
        onLoad_failed: error => root.judge_owner(false)
    }

    function judge_owner(alive: bool): void {
        root.owner_alive = alive;
        root.probed_owner = root.owner_key;
    }
}
