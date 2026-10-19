import Quickshell.Io

IpcHandler {
    required property HyprvimPrompt prompt

    target: "hyprvim_prompt"

    // Returns "ok" once the prompt is shown; HyprVim falls back to its terminal bar on anything else.
    function open(path: string): string {
        return prompt.open_spec(path);
    }

    function close(): void {
        prompt.dismiss();
    }
}
