// home/quickshell/.config/quickshell/services/ScreenshotIpc.qml
import Quickshell.Io

IpcHandler {
    target: "screenshot"

    // Returns "ok" so screenshot.sh can fall back to rofi on anything else.
    function open(): string {
        Screenshot.open_menu();
        return "ok";
    }

    function close(): void {
        if (Popups.open_name === "screenshot") Popups.close();
        Screenshot.cancel();
    }

    function toggle(): string {
        if (Popups.open_name === "screenshot") Popups.close();
        else Screenshot.open_menu();
        return "ok";
    }

    // preset: "toolbar" (or "") shows the toolbar, "ocr" and "record" act on confirm.
    function select(frozen: bool, preset: string): string {
        Screenshot.select(frozen, preset === "toolbar" ? "" : preset);
        return "ok";
    }

    function stop_recording(): void {
        Screenshot.stop_recording();
    }

    function recording_started(pid: string): void {
        Screenshot.recording_started(pid);
    }

    function recording_stopped(): void {
        Screenshot.recording_stopped();
    }
}
