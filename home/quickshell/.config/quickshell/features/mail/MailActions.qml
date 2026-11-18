pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// The two things the popup does to Thunderbird: open its Inbox and step to the next unread message. Both change only what
// Thunderbird shows. Nothing here reads, marks, moves or deletes mail.
Singleton {
    id: root

    // Window classes of the mail clients the bridge's add-on runs in, compared in lower case.
    readonly property var mail_classes: ["thunderbird", "org.mozilla.thunderbird", "eu.betterbird.betterbird", "betterbird"]

    function mail_window() {
        for (const t of Hyprland.toplevels.values) {
            const cls = (t.lastIpcObject && t.lastIpcObject.class ? t.lastIpcObject.class : (t.wayland ? t.wayland.appId : "")).toLowerCase();
            if (root.mail_classes.indexOf(cls) >= 0) return t;
        }
        return null;
    }

    // `run` acts in the mail window the add-on saw last focused and does not raise it, so the window comes forward first.
    function raise_then_run(words) {
        const win = root.mail_window();
        if (win) Hyprland.dispatch("hl.dsp.focus({ window = 'address:0x" + win.address + "' })");
        Quickshell.execDetached(["desertfox", "--app", "thunderbird", "run"].concat(words));
    }

    function open_inbox() {
        root.raise_then_run(["folder.open", "--special=inbox"]);
    }

    function next_unread() {
        root.raise_then_run(["step.unread", "--next", "--all-folders"]);
    }
}
