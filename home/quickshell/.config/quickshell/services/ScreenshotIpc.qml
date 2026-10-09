// home/quickshell/.config/quickshell/services/ScreenshotIpc.qml
import Quickshell.Io

IpcHandler {
    target: "screenshot"

    // Returns "ok" so screenshot.sh can fall back to rofi on anything else.
    function open(): string {
        if (Screenshot.scrolling) Screenshot.stop_scroll();
        else Screenshot.open_menu();
        return "ok";
    }

    function close(): void {
        if (Popups.open_name === "screenshot") Popups.close();
        Screenshot.cancel();
    }

    function toggle(): string {
        if (Screenshot.scrolling) Screenshot.stop_scroll();
        else if (Popups.open_name === "screenshot") Popups.close();
        else Screenshot.open_menu();
        return "ok";
    }

    // preset: "toolbar" (or "") shows the toolbar, "ocr", "record", "scroll_text" and "scroll_image" act on confirm.
    function select(frozen: bool, preset: string): string {
        Screenshot.select(frozen, preset === "toolbar" ? "" : preset);
        return "ok";
    }

    // mode: "pixel" picks a colour; preset as for select.
    function pick(mode: string, preset: string): string {
        Screenshot.select(false, preset === "toolbar" ? "" : preset, mode);
        return "ok";
    }

    // For share-picker: answers the XDPH request by writing its selection, or an empty line, to reply.
    function share(windows: string, reply: string): string {
        return Screenshot.start_share(windows, reply) ? "ok" : "busy";
    }

    function stop_recording(): void {
        Screenshot.stop_recording();
    }

    // "ok" when a bar shows the recording chip.
    function recording_started(pid: string): string {
        Screenshot.recording_started(pid);
        return Screenshot.recording_chips > 0 ? "ok" : "no_chip";
    }

    function recording_stopped(): void {
        Screenshot.recording_stopped();
    }
}
