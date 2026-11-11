import Quickshell.Io

IpcHandler {
    target: "media"

    // Starts the jump to the Firefox tab behind the active player. Answers "jumping", or why not: "no player", "not firefox". The jump itself ends asynchronously and reports a missing bridge or sharing by notice.
    function jump_to_tab(): string {
        return MediaJumpState.jump();
    }
}
