import Quickshell.Io

IpcHandler {
    target: "bareditor"

    // Opens the editor on `monitor`'s bar (e.g. "DP-1"), or the focused monitor's when empty. "no bar" when no monitor has one.
    function open(monitor: string): string {
        return BarEditor.open(monitor) ? "ok" : "no bar";
    }

    function close(): string {
        BarEditor.close();
        return "ok";
    }

    function toggle(): string {
        BarEditor.toggle("");
        return BarEditor.active ? "open" : "closed";
    }

    // JSON: active, mode, focus_screen, selected, picked, sharing, sharing_count, undo, redo.
    function state(): string {
        return BarEditor.state_json();
    }
}
