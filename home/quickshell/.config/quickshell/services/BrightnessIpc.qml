// home/quickshell/.config/quickshell/services/BrightnessIpc.qml
import Quickshell.Io

IpcHandler {
    target: "brightness"

    function refresh(): void {
        Backlight.refresh();
    }
}
