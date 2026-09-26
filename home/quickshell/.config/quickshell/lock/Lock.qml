// home/quickshell/.config/quickshell/lock/Lock.qml
pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import "../services"
import "../theme"

// The session lock: one surface per screen, unlocked only by a PAM success.
Singleton {
    id: root

    // Must stay the first child: reloads match children by index and this restores `locked` before the lock reloads.
    PersistentProperties {
        id: persist
        reloadableId: "lock_state"
        property bool locked: false
        // Set once the compositor confirmed this lock, so a later end is a lost lock, not a refusal.
        property bool held: false
        property bool heal_checked: false
        property bool healing: false

        onLoaded: {
            if (persist.heal_checked) return;
            persist.heal_checked = true;
            heal_check.running = true;
        }
    }

    readonly property bool locked: persist.locked
    property string buffer: ""
    property string pending: ""
    property bool checking: false
    property bool failed: false
    property int fail_count: 0
    property string message: ""
    property string prompt: ""
    property string pam_error: ""
    property bool caps_lock: false
    // True for a while after each key, so the caret only blinks while someone is typing.
    property bool typing: false
    property bool quitting: false
    // PAM succeeded; the session opens once the skin's unlock animation (unlock_ms) has played.
    property bool granted: false
    property int unlock_ms: 0
    property bool saver: false
    // Left alone for long: skins stop their loops.
    property bool dormant: false
    readonly property string flag_script: Quickshell.shellDir + "/scripts/lock-flag"

    signal rejected

    function lock() {
        if (persist.locked) return "locked";
        root.reset_input();
        root.fail_count = 0;
        root.message = "";
        root.granted = false;
        root.wake();
        Popups.close();
        persist.held = false;
        persist.locked = true;
        if (!session_lock.locked) {
            persist.locked = false;
            return "failed";
        }
        return "ok";
    }

    // A fresh qs found the lock of a dead qs: take it over, else hand the screen to hyprlock.
    function heal() {
        console.warn("Lock: taking over the session lock of a qs that exited");
        persist.healing = true;
        Quickshell.execDetached(["notify-send", "-a", "Lock", "-i", "system-lock-screen", "Session re-locked after the bar restarted"]);
        if (root.lock() === "failed") root.heal_fallback();
    }

    function heal_fallback() {
        persist.healing = false;
        Quickshell.execDetached([root.flag_script, "hyprlock"]);
    }

    function state() {
        if (!persist.locked) return "unlocked";
        return session_lock.secure ? "secure" : "pending";
    }

    function reset_input() {
        root.buffer = "";
        root.pending = "";
        root.checking = false;
        root.failed = false;
        root.prompt = "";
        root.pam_error = "";
    }

    function submit() {
        if (root.checking || root.buffer === "") return;
        root.failed = false;
        root.message = "";
        root.pam_error = "";
        if (pam.active && pam.responseRequired) {
            const answer = root.buffer;
            root.buffer = "";
            root.checking = true;
            watchdog.restart();
            pam.respond(answer);
            return;
        }
        root.pending = root.buffer;
        root.buffer = "";
        root.checking = true;
        watchdog.restart();
        if (!pam.start()) root.fail("Could not start authentication");
    }

    function fail(text) {
        watchdog.stop();
        root.checking = false;
        root.pending = "";
        root.prompt = "";
        root.failed = true;
        root.message = text;
        root.rejected();
    }

    function wake() {
        root.saver = false;
        root.dormant = false;
        saver_timer.restart();
        dormant_timer.restart();
    }

    function finish_unlock() {
        if (!root.granted) return;
        root.granted = false;
        persist.locked = false;
        Quickshell.execDetached([root.flag_script, "clear"]);
    }

    // The style's skins/<Name>.qml, else the generic screen.
    function skin_url() {
        const name = Style.lock_name;
        const file = name.charAt(0).toUpperCase() + name.slice(1) + ".qml";
        for (let i = 0; i < skin_files.count; i++) {
            if (skin_files.get(i, "fileName") === file) return Qt.resolvedUrl("skins/" + file);
        }
        return Qt.resolvedUrl("LockScreen.qml");
    }

    function key(event) {
        root.wake();
        if (root.granted) {
            event.accepted = true;
            return;
        }
        root.typing = true;
        typing_timer.restart();
        const ctrl = (event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier);
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit();
        } else if (root.checking) {
            // Input waits until PAM answers.
        } else if (event.key === Qt.Key_Escape || (ctrl && event.key === Qt.Key_U)) {
            root.buffer = "";
        } else if (event.key === Qt.Key_Backspace) {
            root.buffer = ctrl ? "" : root.buffer.slice(0, -1);
        } else if (event.key === Qt.Key_CapsLock) {
            root.caps_lock = !root.caps_lock;
        } else if (!ctrl && event.text !== "" && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            const t = event.text;
            if (t.toUpperCase() !== t.toLowerCase()) root.caps_lock = (t === t.toUpperCase()) !== !!(event.modifiers & Qt.ShiftModifier);
            root.buffer += t;
            root.failed = false;
        } else {
            return;
        }
        event.accepted = true;
    }

    Timer {
        id: typing_timer
        interval: 15000
        onTriggered: root.typing = false
    }

    Timer {
        id: watchdog
        interval: 30000
        onTriggered: {
            pam.abort();
            root.fail("Authentication timed out");
        }
    }

    PamContext {
        id: pam
        config: "login"

        onPamMessage: {
            if (pam.responseRequired) {
                if (root.pending !== "") {
                    const answer = root.pending;
                    root.pending = "";
                    pam.respond(answer);
                } else {
                    watchdog.stop();
                    root.checking = false;
                    root.prompt = pam.message;
                }
            } else if (pam.message !== "") {
                if (pam.messageIsError) root.pam_error = root.pam_error === "" ? pam.message : root.pam_error + "\n" + pam.message;
                else root.message = root.message === "" ? pam.message : root.message + "\n" + pam.message;
            }
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                watchdog.stop();
                root.reset_input();
                root.fail_count = 0;
                root.message = "";
                root.granted = true;
                const delay = Power.on_ac ? Math.max(0, Math.min(2000, root.unlock_ms)) : 0;
                if (delay === 0) root.finish_unlock();
                else unlock_timer.restart();
                return;
            }
            root.fail_count += 1;
            if (result === PamResult.MaxTries) root.fail("Too many attempts");
            else if (root.pam_error !== "") root.fail(root.pam_error);
            else root.fail(result === PamResult.Failed ? "Wrong password" : "Authentication error");
        }

        onError: error => root.fail("Authentication error: " + PamError.toString(error))
    }

    WlSessionLock {
        id: session_lock
        locked: persist.locked

        // Fires when the compositor refuses or ends the lock; drop the target so the next lock() can try again.
        onLockedChanged: {
            if (!session_lock.locked && persist.locked) {
                console.warn("Lock: the session lock ended without authentication");
                pam.abort();
                persist.locked = false;
                if (persist.healing) root.heal_fallback();
                else if (persist.held && !root.quitting) lost_clear.restart();
            }
        }

        onSecureChanged: {
            if (session_lock.secure && persist.locked) {
                persist.held = true;
                persist.healing = false;
                Quickshell.execDetached([root.flag_script, "set", String(Quickshell.processId)]);
            }
        }

        WlSessionLockSurface {
            color: Theme.bg_crust

            // Keys live here, not in the loaded screen, so a broken screen still takes the password.
            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => root.key(event)

                Loader {
                    id: screen_loader
                    anchors.fill: parent

                    Component.onCompleted: {
                        screen_loader.setSource(root.skin_url(), { ctx: live_ctx });
                        if (screen_loader.status === Loader.Error) screen_loader.setSource(Qt.resolvedUrl("LockScreen.qml"), { ctx: live_ctx });
                        const ms = screen_loader.item ? screen_loader.item.unlock_ms : undefined;
                        root.unlock_ms = typeof ms === "number" ? ms : 0;
                    }
                }

                Text {
                    visible: screen_loader.status === Loader.Error
                    anchors.centerIn: parent
                    text: root.checking ? "Checking" : "Locked. Type your password and press Enter. " + "*".repeat(root.buffer.length) + (root.failed ? "\n" + root.message : "")
                    horizontalAlignment: Text.AlignHCenter
                    color: root.failed ? Theme.error : Theme.fg_core
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size
                }
            }
        }
    }

    // The compositor ended a held lock while qs lives on (e.g. a forced unlock); a dying qs never gets here.
    Timer {
        id: lost_clear
        interval: 500
        onTriggered: {
            if (!root.quitting && !persist.locked) Quickshell.execDetached([root.flag_script, "clear"]);
        }
    }

    Connections {
        target: Qt.application
        function onAboutToQuit() { root.quitting = true; }
    }

    Process {
        id: heal_check
        command: [root.flag_script, "check", String(Quickshell.processId)]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "relock") root.heal();
            }
        }
    }

    Timer {
        id: unlock_timer
        interval: Math.max(1, Math.min(2000, root.unlock_ms))
        onTriggered: root.finish_unlock()
    }

    Timer {
        id: saver_timer
        interval: 30000
        onTriggered: {
            if (!persist.locked) return;
            if (Power.on_ac && !root.granted && !root.checking && root.buffer === "") root.saver = true;
            else saver_timer.restart();
        }
    }

    Timer {
        id: dormant_timer
        interval: 600000
        onTriggered: root.dormant = persist.locked
    }

    FolderListModel {
        id: skin_files
        folder: Qt.resolvedUrl("skins")
        nameFilters: ["*.qml"]
        showDirs: false
    }

    LockCtx {
        id: live_ctx
        buffer_length: root.buffer.length
        checking: root.checking
        failed: root.failed
        fail_count: root.fail_count
        message: root.message !== "" ? root.message : root.pam_error
        caps_lock: root.caps_lock
        typing: root.typing
        granted: root.granted
        saver: root.saver && Power.on_ac
        animate: Power.on_ac && !root.dormant
    }

    Connections {
        target: root
        function onRejected() { live_ctx.rejected(); }
    }
}
