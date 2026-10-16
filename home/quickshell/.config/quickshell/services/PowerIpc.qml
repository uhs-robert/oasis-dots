import Quickshell.Io

IpcHandler {
    target: "power"

    // Drops the confirm prompt for `action` from the focused screen's center island.
    function confirm(action: string): void {
        if (Power.actions.indexOf(action) < 0) return;
        Popups.power_action = action;
        Popups.open("power", undefined);
    }

    // Runs `action` with no prompt, for a caller that has already asked (voxcmd's confirm card).
    function run(action: string): void {
        if (Power.actions.indexOf(action) < 0) return;
        Power.run(action);
    }
}
