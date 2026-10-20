pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Whether voxtype-duck holds the output sink lowered, read from the journal it keeps while ducked
// ($XDG_RUNTIME_DIR/voxcmd/duck.json, with the sink and the volume to return to). The follower deletes the file after
// its last volume write, so a quiet period after this turns false belongs to the one that reads it.
Singleton {
    id: root

    property bool ducked: false

    FileView {
        id: duck_file
        path: VoxSessionState.voxcmd_dir + "/duck.json"
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.ducked = JSON.parse(text()).sink_id !== undefined;
            } catch (e) {
                // A half-written file never shows: the follower renames it into place.
                root.ducked = false;
            }
        }
        onLoadFailed: error => root.ducked = false
    }

    // VoxSessionState finds the folder once voxcmd has made it; a watch reports a file only in a folder that exists.
    Connections {
        target: VoxSessionState
        function onVoxcmd_dir_existsChanged() {
            duck_file.reload();
        }
    }
}
