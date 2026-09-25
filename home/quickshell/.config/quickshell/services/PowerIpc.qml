// home/quickshell/.config/quickshell/services/PowerIpc.qml
import Quickshell.Io

IpcHandler {
    target: "power"

    readonly property var indices: ({ lock: 2, logout: 3, reboot: 4, poweroff: 5 })

    // Opens the Start popup on the focused screen's bar, straight into confirm mode for `action`.
    function confirm(action: string): void {
        const index = indices[action];
        if (index === undefined) return;
        Popups.pending_confirm = index;
        Popups.open("start", undefined);
    }
}
