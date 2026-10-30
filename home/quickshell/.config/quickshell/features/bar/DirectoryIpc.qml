import Quickshell.Io

IpcHandler {
    target: "dir"

    // Called by the tmux hooks in home/tmux/.tmux.conf, which cannot reach Hyprland's events.
    function refresh(): void {
        DirectoryRefresh.request();
    }
}
