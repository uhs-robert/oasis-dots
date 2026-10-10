// home/quickshell/.config/quickshell/services/CommandStatusIpc.qml
import Quickshell.Io

IpcHandler {
    target: "cmdstatus"

    // Reruns one entry's command now, or every entry for "". Answers "unknown" for an id the config lacks.
    function refresh(id: string): string {
        return CommandStatusState.refresh(id) ? "ok" : "unknown";
    }
}
