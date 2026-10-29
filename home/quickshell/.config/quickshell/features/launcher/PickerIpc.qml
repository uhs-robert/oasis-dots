import Quickshell
import Quickshell.Io

Scope {
    id: root

    // Kept off the IpcHandler, which exposes every property it has.
    required property PickerVoice voice

    IpcHandler {
        target: "picker"

        // Returns "ok" so callers can fall back to rofi on anything else.
        function open(name: string): string {
            return Pickers.open(name, null) ? "ok" : "unknown";
        }

        function open_with(name: string, arg: string): string {
            return Pickers.open(name, null, undefined, undefined, undefined, arg) ? "ok" : "unknown";
        }

        function toggle(name: string): string {
            return Pickers.toggle(name, null) ? "ok" : "unknown";
        }

        function close(): void {
            Pickers.close();
        }

        // Voice answers to the open picker, by the token it published (PickerVoice).
        function answer(token: string, text: string): string {
            return root.voice.answer(token, text);
        }

        // `token` may be empty: see PickerVoice.expand.
        function expand(index: int, token: string): string {
            return root.voice.expand(index, token);
        }

        function cancel(token: string): string {
            return root.voice.cancel(token);
        }
    }
}
