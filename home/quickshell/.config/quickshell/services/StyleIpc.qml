// home/quickshell/.config/quickshell/services/StyleIpc.qml
import Quickshell.Io
import "../theme"

IpcHandler {
    target: "style"

    function set(name: string): void {
        Style.set(name);
    }

    function cycle(): void {
        Style.cycle();
    }

    function get(): string {
        return Style.name;
    }
}
