// home/quickshell/.config/quickshell/services/StyleIpc.qml
import Quickshell.Io
import "../theme"
import "../components/transitions"

IpcHandler {
    target: "style"

    function set(name: string): void {
        Transitions.commit(name);
    }

    function cycle(): void {
        Transitions.commit(Style.names[(Style.names.indexOf(Style.saved_name) + 1) % Style.names.length]);
    }

    function get(): string {
        return Style.name;
    }

    // A style name, "follow" to match the active style, or "simple" for the plain lock screen.
    function set_lock(name: string): string {
        return Style.set_lock_style(name) ? "ok" : "unknown";
    }

    function get_lock(): string {
        return Style.lock_style;
    }

    // primary, secondary, green, amber or white.
    function set_lock_tint(name: string): string {
        return Style.set_lock_tint(name) ? "ok" : "unknown";
    }

    function get_lock_tint(): string {
        return Style.lock_tint;
    }

    function toggle_cava_line(): void {
        Style.set_cava_line(!Style.cava_line);
    }

    function get_cava_line(): bool {
        return Style.cava_line;
    }
}
