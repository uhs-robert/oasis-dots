import Quickshell.Io

IpcHandler {
    required property WhichKey whichkey

    target: "hyprvim_whichkey"

    function open(path: string): void {
        whichkey.show_payload(path);
    }

    function close(): void {
        whichkey.hide_now();
    }
}
