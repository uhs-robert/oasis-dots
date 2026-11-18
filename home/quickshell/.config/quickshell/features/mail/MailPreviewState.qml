pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.core
import qs.features.lock
import qs.features.screenshot
import "MailParse.js" as Parse

// The newest unread headers (sender, subject, date) of one folder, for the popup. Asked for when the popup opens or its
// cursor moves to another folder, never on a timer, and never while the screen could be seen by someone else.
Singleton {
    id: root

    readonly property int limit: 5

    // The portal's PipeWire node, as ScreenShare.qml reads it (that one is not a singleton to read).
    readonly property bool shared: Pipewire.nodes.values.some(n => n.name === "xdg-desktop-portal-hyprland")
    // Whether headers may be fetched and drawn at all.
    readonly property bool allowed: Parse.preview_allowed(MailSettings.mail_preview, Screenshot.recording, root.shared, Lock.locked)

    // [{ from, subject, date }] for `folder_id`, empty while nothing is allowed or loaded.
    property var rows: []
    // "" idle, "loading", "ok" or "failed".
    property string status: ""
    property string folder_id: ""
    property string wanted_id: ""

    onAllowedChanged: if (!root.allowed) root.clear()

    function clear() {
        root.rows = [];
        root.status = "";
        root.folder_id = "";
        root.wanted_id = "";
    }

    // Ask for a folder's headers. An unsafe or empty id, or a screen someone may see, asks for nothing.
    function show(id) {
        if (!root.allowed || id === "") {
            root.clear();
            return;
        }
        if (id === root.folder_id && root.status !== "") return;
        root.wanted_id = id;
        root.rows = [];
        root.status = "loading";
        root.folder_id = id;
        root.fetch();
    }

    // While a fetch is still going `run()` does nothing, and its end starts the wanted folder's.
    function fetch() {
        if (poll.run()) poll.asked = root.wanted_id;
    }

    PolledCommand {
        id: poll
        command: ["sh", "-c", 'exec desertfox --app thunderbird mail list "$1" --unread --limit "$2" --json', "sh", root.wanted_id, String(root.limit)]
        collect_stderr: true
        timeout_ms: 20000
        property string asked: ""
        onFinished: (code, out) => {
            // The popup or the gate closed mid-fetch: nothing is wanted, so nothing is fetched again.
            if (root.wanted_id === "") return;
            const answered = poll.asked;
            if (answered !== root.wanted_id) {
                poll.asked = root.wanted_id;
                poll.run();
                return;
            }
            const parsed = code === 0 ? Parse.parse_messages(out) : { ok: false };
            // The headers are dropped if the screen became visible to others while the command ran.
            if (!root.allowed) {
                root.clear();
                return;
            }
            root.rows = parsed.ok ? parsed.messages : [];
            root.status = parsed.ok ? "ok" : "failed";
        }
    }
}
