// home/quickshell/.config/quickshell/services/PopupIpc.qml
import Quickshell.Io

IpcHandler {
    target: "popup"

    function open(name: string): void {
        Popups.open(name, undefined);
    }

    function close(): void {
        Popups.close();
    }

    function toggle(name: string): void {
        Popups.toggle(name, undefined);
    }
}
