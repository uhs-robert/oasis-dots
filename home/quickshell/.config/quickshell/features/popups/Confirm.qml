pragma Singleton
import QtQuick
import Quickshell
import qs.features.voice

// The yes/no question the confirm card asks for a shell caller (voxcmd-confirm), which blocks reading result_path.
// Every way the card ends writes one answer there: "yes", or "no" for No, Esc, the scrim, the timeout or another popup.
Singleton {
    id: root

    property string question: ""
    property string result_path: ""
    property bool asking: false
    // Voice replies keep the card waiting: the countdown runs only while voxtype is neither recording nor transcribing.
    readonly property bool listening: VoxtypeState.recording || VoxtypeState.transcribing
    readonly property int timeout_ms: 10000

    function ask(question, result_path) {
        // A newer question replaces an unanswered one, whose caller then reads a no.
        root.answer(false);
        root.question = question;
        root.result_path = result_path;
        root.asking = true;
        Popups.open("confirm", undefined);
    }

    function answer(yes) {
        if (!root.asking) return;
        root.asking = false;
        // timeout: with no reader left on the FIFO the redirect would block forever.
        Quickshell.execDetached(["timeout", "2", "sh", "-c", "printf '%s\\n' \"$1\" > \"$2\"", "sh", yes ? "yes" : "no", root.result_path]);
        if (Popups.open_name === "confirm") Popups.close();
    }

    // For a caller already answered another way (a voice reply into its FIFO): closes its card without writing.
    // A newer question's card stays.
    function dismiss(result_path) {
        if (!root.asking || root.result_path !== result_path) return;
        root.asking = false;
        if (Popups.open_name === "confirm") Popups.close();
    }

    Timer {
        running: root.asking && !root.listening
        interval: root.timeout_ms
        onTriggered: root.answer(false)
    }

    Connections {
        target: Popups
        function onOpen_nameChanged() {
            if (Popups.open_name !== "confirm") root.answer(false);
        }
    }
}
