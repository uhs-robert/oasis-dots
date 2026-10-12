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

    // "closed", "opening <name>" while it animates in, or "open <name>" once it is fully drawn.
    function state(): string {
        if (Popups.open_name === "") return "closed";
        return (Popups.settled_name === Popups.open_name ? "open " : "opening ") + Popups.open_name;
    }
}
