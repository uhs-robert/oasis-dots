// home/quickshell/.config/quickshell/services/PickerIpc.qml
import Quickshell.Io

IpcHandler {
    target: "picker"

    // Returns "ok" so callers can fall back to rofi on anything else.
    function open(name: string): string {
        return Pickers.open(name, null) ? "ok" : "unknown";
    }

    function toggle(name: string): string {
        return Pickers.toggle(name, null) ? "ok" : "unknown";
    }

    function close(): void {
        Pickers.close();
    }
}
