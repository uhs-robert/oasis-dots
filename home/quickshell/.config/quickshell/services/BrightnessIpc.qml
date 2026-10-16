import Quickshell.Io

IpcHandler {
    target: "brightness"

    function refresh(): void {
        Backlight.refresh();
    }
}
