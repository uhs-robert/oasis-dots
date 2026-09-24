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

    function set_bar(on: bool): void {
        Style.set_bar(on);
    }

    function toggle_bar(): void {
        Style.set_bar(!Style.style_bar);
    }

    function get_bar(): bool {
        return Style.style_bar;
    }
}
