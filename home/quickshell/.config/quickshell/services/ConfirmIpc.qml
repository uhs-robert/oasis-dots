// home/quickshell/.config/quickshell/services/ConfirmIpc.qml
import Quickshell.Io

IpcHandler {
    target: "confirm"

    // Drops the confirm card from the focused screen's center island; the answer goes to result_path.
    // Returns "ok" so callers can fall back to rofi on anything else.
    function ask(question: string, result_path: string): string {
        Confirm.ask(question, result_path);
        return "ok";
    }

    function dismiss(result_path: string): void {
        Confirm.dismiss(result_path);
    }
}
