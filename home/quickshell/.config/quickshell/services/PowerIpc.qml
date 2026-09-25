// home/quickshell/.config/quickshell/services/PowerIpc.qml
import Quickshell.Io

IpcHandler {
    target: "power"

    // Opens the Start popup on the focused screen's bar, straight into confirm mode for `action`.
    function confirm(action: string): void {
        const index = ({ lock: 2, logout: 3, reboot: 4, poweroff: 5 })[action];
        if (index === undefined) return;
        Popups.pending_confirm = index;
        Popups.open("start", undefined);
    }
}
