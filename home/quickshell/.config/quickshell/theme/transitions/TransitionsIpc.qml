import Quickshell.Io

IpcHandler {
    target: "transition"

    // Plays a kind or a style's transition on every bar, on battery too.
    function play(name: string): void {
        Transitions.request(name, true);
    }
}
