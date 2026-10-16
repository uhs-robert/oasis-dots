pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The numbered boxes voxcmd's click shows when several on-screen texts match (voxcmd-hints blocks reading result_path).
// Every way the overlay ends writes one answer there: the 1-based number of the box picked, or an empty line for Esc,
// a click elsewhere, the timeout or a newer overlay.
Singleton {
    id: root

    property bool active: false
    property string label: ""
    // [{label, x, y, w, h}] in global logical coordinates, at most max_choices.
    property var choices: []
    property string result_path: ""
    // Holds the keyboard, like Zoom's focus_screen: the screen the first box is on.
    property string focus_screen: ""
    // Voice replies keep the overlay up: the countdown runs only while voxtype is neither recording nor transcribing.
    readonly property bool listening: VoxtypeState.recording || VoxtypeState.transcribing
    readonly property int timeout_ms: 10000
    readonly property int max_choices: 10

    // Returns false for a spec that has no usable boxes or more than max_choices (the extra would vanish unseen), so the
    // caller falls back to the text picker.
    function open(spec_path) {
        let spec;
        try {
            spec_file.path = "";
            spec_file.path = spec_path;
            spec = JSON.parse(spec_file.text());
        } catch (e) {
            console.warn("ClickHints: unreadable spec " + spec_path + " (" + e + ")");
            return false;
        }
        const boxes = (spec.choices ?? []).map(c => ({
            label: String(c.label ?? ""),
            x: Number(c.x),
            y: Number(c.y),
            w: Number(c.w),
            h: Number(c.h)
        }));
        if (boxes.length === 0 || boxes.length > root.max_choices || !spec.result_path || boxes.some(b => isNaN(b.x + b.y + b.w + b.h))) return false;
        // A newer overlay replaces an unanswered one, whose caller then reads a cancel.
        root.answer(0);
        root.label = spec.label ?? "";
        root.choices = boxes;
        root.result_path = spec.result_path;
        const first = boxes[0];
        const screen = root.screen_at(first.x + first.w / 2, first.y + first.h / 2) ?? Quickshell.screens[0];
        root.focus_screen = screen ? screen.name : "";
        root.active = true;
        return true;
    }

    // The 1-based number picked, or 0 for a cancel.
    function answer(number) {
        if (!root.active) return;
        root.active = false;
        // timeout: with no reader left on the FIFO the redirect would block forever.
        Quickshell.execDetached(["timeout", "2", "sh", "-c", "printf '%s\\n' \"$1\" > \"$2\"", "sh", number > 0 ? String(number) : "", root.result_path]);
    }

    // For a caller already answered another way (a voice reply into its FIFO): closes the overlay without writing.
    // A newer overlay stays.
    function dismiss(result_path) {
        if (!root.active || root.result_path !== result_path) return;
        root.active = false;
    }

    function screen_at(x, y) {
        return Quickshell.screens.find(s => x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) ?? null;
    }

    FileView {
        id: spec_file
        printErrors: false
        blockLoading: true
    }

    Timer {
        running: root.active && !root.listening
        interval: root.timeout_ms
        onTriggered: root.answer(0)
    }
}
