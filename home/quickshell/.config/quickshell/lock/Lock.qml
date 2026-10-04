// home/quickshell/.config/quickshell/lock/Lock.qml
pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import "../services"
import "../theme"
// Skins load by URL; importing the folder lets Quickshell register the component folders they import.
import "skins"
import "skins/ui"

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
        // JSON map of output name to backdrop screenshot, kept so a reload while locked still draws it.
        property string backdrops: ""

        onLoaded: {
            if (persist.heal_checked) return;
            persist.heal_checked = true;
            capture.clear();
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
    property bool music_armed: false
    property bool insert: false
    property bool arm_on_engage: false
    readonly property string flag_script: Quickshell.shellDir + "/scripts/lock-flag"
    readonly property var backdrop_files: {
        try {
            return JSON.parse(persist.backdrops || "{}");
        } catch (e) {
            return {};
        }
    }

    signal rejected

    // Screenshots the outputs first when the screen draws a backdrop; the lock follows within capture.cap_ms.
    // A manual lock starts its music right away; an automatic one (`auto`) waits for the first key.
    function lock(auto) {
        if (persist.locked) return "locked";
        if (capture.running) {
            if (!auto) root.arm_on_engage = true;
            return "ok";
        }
        root.arm_on_engage = !auto;
        Popups.close();
        if (!root.wants_backdrop()) return root.engage({});
        capture.start(Quickshell.screens.map(s => s.name));
        return "ok";
    }

    function engage(files) {
        if (persist.locked) return "locked";
        root.reset_input();
        root.fail_count = 0;
        root.message = "";
        root.granted = false;
        root.disarm_music();
        if (root.arm_on_engage) root.arm_music();
        root.arm_on_engage = false;
        live_ctx.scene = "";
        root.wake();
        persist.held = false;
        persist.backdrops = JSON.stringify(files);
        persist.locked = true;
        if (!session_lock.locked) {
            persist.locked = false;
            root.drop_backdrop();
            return "failed";
        }
        ThemeAudio.play_lock("lock");
        return "ok";
    }

    // The generic screen draws the backdrop unless it is off; skins in backdrop_skins always take one for their own intro.
    readonly property var backdrop_skins: ["Goldeneye.qml"]

    function wants_backdrop(style_name) {
        const url = String(root.skin_url(style_name));
        if (root.backdrop_skins.some(f => url.endsWith("/lock/skins/" + f))) return true;
        return Style.lock_backdrop !== "off" && url === String(Qt.resolvedUrl("LockScreen.qml"));
    }

    function drop_backdrop() {
        persist.backdrops = "";
        capture.clear();
    }

    // A fresh qs found the lock of a dead qs: take it over, else hand the screen to hyprlock.
    function heal() {
        console.warn("Lock: taking over the session lock of a qs that exited");
        persist.healing = true;
        Quickshell.execDetached(["notify-send", "-a", "Lock", "-i", "system-lock-screen", "Session re-locked after the bar restarted"]);
        if (root.engage({}) === "failed") root.heal_fallback();
    }

    function heal_fallback() {
        persist.healing = false;
        Quickshell.execDetached([root.flag_script, "hyprlock"]);
    }

    function state() {
        if (capture.running) return "pending";
        if (!persist.locked) return "unlocked";
        return session_lock.secure ? "secure" : "pending";
    }

    function reset_input() {
        root.buffer = "";
        root.insert = false;
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
        root.insert = false;
        root.failed = true;
        root.message = text;
        ThemeAudio.play_lock("error");
        root.rejected();
    }

    function arm_music() {
        root.music_armed = true;
        music_timer.restart();
    }

    function disarm_music() {
        root.music_armed = false;
        music_timer.stop();
    }

    function wake() {
        root.saver = false;
        saver_timer.restart();
    }

    // Reboots, powers off or reboots to firmware setup from the lock; the skin asking has already confirmed.
    function power(action) {
        if (!persist.locked || ["reboot", "poweroff", "firmware"].indexOf(action) < 0) return;
        if (action === "firmware") Quickshell.execDetached(["systemctl", "reboot", "--firmware-setup"]);
        else Quickshell.execDetached(["systemctl", action]);
    }

    function finish_unlock() {
        if (!root.granted) return;
        root.granted = false;
        root.disarm_music();
        persist.locked = false;
        root.drop_backdrop();
        Quickshell.execDetached([root.flag_script, "clear"]);
    }

    // The style's skins/<Name>.qml, else the generic screen; `style_name` defaults to the lock's own.
    function skin_url(style_name) {
        return LockSkins.url_for(style_name || Style.lock_name);
    }

    // True when `skin` defines handle_key(event) and it returns exactly true; a throwing skin takes nothing.
    function skin_takes(event, skin) {
        if (!skin || typeof skin.handle_key !== "function") return false;
        try {
            return skin.handle_key(event) === true;
        } catch (e) {
            console.warn("Lock: skin handle_key failed: " + e);
            return false;
        }
    }

    // NORMAL mode (not insert) offers keys to `skin` while the buffer is empty and PAM waits on nothing; `i` or any typed key enters INSERT, Esc on an empty buffer leaves it.
    function key(event, skin) {
        root.wake();
        root.arm_music();
        if (root.granted) {
            // A fresh press skips the unlock animation; a held Enter from the submit does not.
            if (!event.isAutoRepeat) {
                unlock_timer.stop();
                root.finish_unlock();
            }
            event.accepted = true;
            return;
        }
        root.typing = true;
        typing_timer.restart();
        const ctrl = (event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier);
        const was_insert = root.insert;
        if (event.key === Qt.Key_Escape && root.insert && root.buffer === "" && !root.checking) root.insert = false;
        const normal = !root.insert && !root.checking && root.buffer === "" && root.prompt === "";
        if (normal && root.skin_takes(event, skin)) {
            event.accepted = true;
            return;
        }
        if (was_insert && !root.insert) {
            event.accepted = true;
            return;
        }
        if (normal && !ctrl && event.text === "i") {
            root.insert = true;
            event.accepted = true;
            return;
        }
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
            root.insert = true;
            root.failed = false;
        } else {
            return;
        }
        event.accepted = true;
    }

    Timer {
        id: music_timer
        interval: 120000
        onTriggered: root.music_armed = false
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
                ThemeAudio.play_lock("unlock");
                const delay = Power.on_ac ? Math.max(0, Math.min(4000, root.unlock_ms)) : 0;
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
                root.drop_backdrop();
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
            id: surface
            color: Theme.bg_crust

            // Keys live here, not in the loaded screen, so a broken screen still takes the password.
            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => root.key(event, screen_loader.item)

                ModeIndicator {
                    z: 1000
                    skin: screen_loader.item
                    ctx: live_ctx
                    font_fallback: Style.mono_font
                }

                Loader {
                    id: screen_loader
                    anchors.fill: parent

                    Component.onCompleted: {
                        screen_loader.setSource(root.skin_url(), { ctx: live_ctx });
                        if (screen_loader.status === Loader.Error) screen_loader.setSource(Qt.resolvedUrl("LockScreen.qml"), { ctx: live_ctx });
                        if (screen_loader.item && "screen_name" in screen_loader.item) screen_loader.item.screen_name = Qt.binding(() => surface.screen ? surface.screen.name : "");
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
        interval: Math.max(1, Math.min(4000, root.unlock_ms))
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

    LockCapture {
        id: capture
        prefix: "qs-lock"
        onFinished: files => root.engage(files)
    }

    Binding {
        target: ThemeAudio
        property: "lock_active"
        value: persist.locked
    }

    Binding {
        target: ThemeAudio
        property: "lock_armed"
        value: root.music_armed
    }

    LockCtx {
        id: live_ctx
        buffer_length: root.buffer.length
        checking: root.checking
        failed: root.failed
        fail_count: root.fail_count
        message: root.message !== "" ? root.message : root.pam_error
        prompt: root.prompt
        caps_lock: root.caps_lock
        typing: root.typing
        insert: root.insert
        granted: root.granted
        saver: root.saver && Power.on_ac
        animate: Power.on_ac
        backdrops: root.backdrop_files
        power_live: true
        sound: true
        music_armed: root.music_armed
    }

    Connections {
        target: root
        function onRejected() { live_ctx.rejected(); }
    }

    Connections {
        target: live_ctx
        function onPower_request(action) { root.power(action); }
    }
}
