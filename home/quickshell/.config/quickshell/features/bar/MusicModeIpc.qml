import Quickshell.Io
import qs.features.settings

// The `music` target voice and binds use to switch music mode.
IpcHandler {
    target: "music"

    function set(on: bool): void {
        MusicModeSettings.set_on(on);
    }

    function toggle(): void {
        MusicModeSettings.set_on(!MusicModeSettings.on);
    }

    function state(): string {
        return MusicModeSettings.on ? "on" : "off";
    }
}
