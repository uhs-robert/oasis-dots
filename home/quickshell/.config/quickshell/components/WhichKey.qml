// home/quickshell/.config/quickshell/components/WhichKey.qml
import QtQuick
import Quickshell
import Quickshell.Io

// HyprVim's which-key HUD over its `hyprvim_whichkey` IPC target; the window is built while shown and for a while after.
Scope {
    id: root

    property bool wanted: false
    property bool shown: false
    property var payload: ({})

    IpcHandler {
        target: "hyprvim_whichkey"

        function open(path: string): void {
            root.wanted = true;
            payload_file.path = path;
            payload_file.reload();
        }

        function close(): void {
            root.wanted = false;
            root.shown = false;
        }
    }

    FileView {
        id: payload_file
        printErrors: false
        onLoaded: {
            if (!root.wanted) return;
            try {
                root.payload = JSON.parse(text());
                root.shown = (root.payload.items || []).length > 0;
            } catch (e) {
                console.warn("WhichKey: invalid payload (" + e + ")");
            }
        }
    }

    // Keeps the window between key presses so a burst of submaps doesn't rebuild it each time.
    Timer {
        id: linger
        interval: 30000
    }

    onShownChanged: if (!root.shown) linger.restart()

    LazyLoader {
        active: root.shown || linger.running

        WhichKeyPanel {
            payload: root.payload
            visible: root.shown
        }
    }
}
