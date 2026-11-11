import Quickshell.Io

// Keyboard access to the now-playing chip: `qs ipc call now_playing jump` goes to the tab, `pause` pauses it. Both do
// nothing while no tab plays. Bind them from the Hyprland config; none are bound here.
IpcHandler {
    target: "now_playing"

    function jump(): void {
        NowPlayingState.jump();
    }

    function pause(): void {
        NowPlayingState.pause();
    }
}
