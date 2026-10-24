import Quickshell.Io
import qs.theme
import qs.theme.transitions
import qs.features.audio

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

    // The effects pack for every style; "" follows each style's own (Settings > Theme audio > Effects pack).
    function set_effects_pack(name: string): string {
        return ThemeAudio.set_pack(name) ? "ok" : "unknown";
    }

    function get_effects_pack(): string {
        return ThemeAudio.choice;
    }

    // Interface sounds (cursor, confirm, cancel), Settings > Theme audio > Interface sounds.
    function set_ui_sounds(on: bool): void {
        ThemeAudio.set_flag("ui", on);
    }

    function get_ui_sounds(): bool {
        return ThemeAudio.ui;
    }

    // A style name, "follow" to match the active style, or "simple" for the plain lock screen.
    function set_lock(name: string): string {
        return Style.set_lock_style(name) ? "ok" : "unknown";
    }

    function get_lock(): string {
        return Style.lock_style;
    }

    // A name from Style.lock_tints: primary, secondary, a terminal colour (red to purple), white or classic.
    function set_lock_tint(name: string): string {
        return Style.set_lock_tint(name) ? "ok" : "unknown";
    }

    function get_lock_tint(): string {
        return Style.lock_tint;
    }

    // pixelate, blur or off: the simple lock screen's desktop backdrop.
    function set_lock_backdrop(name: string): string {
        return Style.set_lock_backdrop(name) ? "ok" : "unknown";
    }

    function get_lock_backdrop(): string {
        return Style.lock_backdrop;
    }

    function toggle_cava_line(): void {
        Style.set_cava_line(!Style.cava_line);
    }

    function get_cava_line(): bool {
        return Style.cava_line;
    }

    function set_cava_visual(v: string): string {
        return Style.set_cava_visual(v) ? "ok" : "unknown";
    }

    function get_cava_visual(): string {
        return Style.cava_visual;
    }
}
