pragma Singleton
import QtQuick
import Quickshell
import qs.core
import "MailParse.js" as Parse

// Unread counts per folder from Thunderbird, read through the DesertFox command line and DesertBird's bridge. Polled:
// the bridge has no unread event.
Singleton {
    id: root

    // "unavailable" until a run says otherwise: no CLI, no Thunderbird or the bridge off are all normal, so the bar stays quiet.
    property string state: "unavailable"
    property var folders: []
    property bool truncated: false
    // The bridge's own refusal text, such as the share setting to turn on.
    property string message: ""

    readonly property var counted_folders: Parse.counted(root.folders, { trash: MailSettings.skip_trash, junk: MailSettings.skip_junk })
    readonly property int total: Parse.total_unread(root.counted_folders)
    readonly property bool ok: root.state === "ok"
    readonly property bool refused: root.state === "refused"

    function refresh() {
        poll.run();
    }

    PolledCommand {
        id: poll
        // Through sh so a missing desertfox exits 127, read as unavailable, instead of failing to start.
        command: ["sh", "-c", "exec desertfox --app thunderbird mail folders --json"]
        interval_ms: MailSettings.interval_s * 1000
        collect_stderr: true
        // A call that hangs (Thunderbird busy) must not hold the next one off for ever.
        timeout_ms: 20000
        onFinished: (code, out, err) => {
            const result = Parse.classify(code, out, err);
            root.state = result.state;
            root.folders = result.folders;
            root.truncated = result.truncated;
            root.message = result.message;
        }
        onStart_failed: root.state = "unavailable"
    }
}
