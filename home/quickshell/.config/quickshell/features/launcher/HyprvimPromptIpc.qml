import Quickshell
import Quickshell.Io

Scope {
    id: root

    // Kept off the IpcHandler, which exposes every property it has.
    required property HyprvimPrompt prompt

    IpcHandler {
        target: "hyprvim_prompt"

        // Returns "ok" once the prompt is shown; HyprVim falls back to its terminal bar on anything else.
        function open(path: string): string {
            return root.prompt.open_spec(path);
        }

        function close(): void {
            root.prompt.dismiss();
        }
    }
}
