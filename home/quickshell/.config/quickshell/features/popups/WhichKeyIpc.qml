import Quickshell
import Quickshell.Io

Scope {
    id: root

    // Kept off the IpcHandler, which exposes every property it has.
    required property WhichKey whichkey

    IpcHandler {
        target: "hyprvim_whichkey"

        function open(path: string): void {
            root.whichkey.show_payload(path);
        }

        function close(): void {
            root.whichkey.hide_now();
        }
    }
}
