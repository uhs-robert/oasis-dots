// home/quickshell/.config/quickshell/services/ClickHintsIpc.qml
import Quickshell.Io

IpcHandler {
    target: "clickhints"

    // Shows numbered boxes over the screen from the JSON spec file {label, choices: [{label, x, y, w, h}], result_path};
    // the answer goes to result_path. Returns "ok" so callers can fall back to the text picker on anything else.
    function open(spec_path: string): string {
        return ClickHints.open(spec_path) ? "ok" : "invalid";
    }

    function dismiss(result_path: string): void {
        ClickHints.dismiss(result_path);
    }

    // "open" or "closed", for the shadow skill's wait.
    function state(): string {
        return ClickHints.active ? "open" : "closed";
    }
}
