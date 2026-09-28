// home/quickshell/.config/quickshell/services/PowerIpc.qml
import Quickshell.Io

IpcHandler {
    target: "power"

    // Drops the confirm prompt for `action` from the focused screen's center island.
    function confirm(action: string): void {
        if (Power.actions.indexOf(action) < 0) return;
        Popups.power_action = action;
        Popups.open("power", undefined);
    }
}
