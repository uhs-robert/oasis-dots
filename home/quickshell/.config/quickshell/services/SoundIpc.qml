import Quickshell.Io

IpcHandler {
    target: "sound"

    // A kind from ThemeAudio.kinds. "alarm" always rings (voxcmd timers); the rest only when their category is on.
    function play(kind: string): string {
        if (ThemeAudio.kinds.indexOf(kind) < 0) return "unknown";
        if (kind === "alarm") ThemeAudio.play_alarm();
        else ThemeAudio.play(kind);
        return "ok";
    }
}
