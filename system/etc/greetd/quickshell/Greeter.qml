// /etc/greetd/quickshell/Greeter.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import Quickshell.Services.UPower

// Login state and the greetd conversation; without a greetd socket it runs as a preview that accepts any password but "wrong".
Singleton {
    id: root

    readonly property bool preview: !Greetd.available
    readonly property string state_dir: Quickshell.env("QS_GREETER_STATE") || ""
    readonly property string data_dir: "/var/lib/qs-greeter"

    // The bar keeps /var/lib/qs-greeter/greeter.json current; the copy from the last greeter-sync covers a missing or bad one.
    property FileView live_settings_file: FileView {
        path: root.data_dir + "/greeter.json"
        blockLoading: true
        printErrors: false
    }
    property FileView settings_file: FileView {
        path: Quickshell.shellDir + "/greeter.json"
        blockLoading: true
        printErrors: false
    }
    readonly property var settings: root.parse_settings(root.live_settings_file.text()) || root.parse_settings(root.settings_file.text()) || {}
    // A user picked on the login screen, else the saved one.
    property string chosen: ""
    readonly property string user: root.chosen || root.settings.user || (root.users.length > 0 ? root.users[0].name : "")

    property FileView passwd_file: FileView {
        path: "/etc/passwd"
        blockLoading: true
        printErrors: false
    }
    // Users with a UID in the login range and a real shell, as {name, full}; the saved user first.
    readonly property var users: {
        const out = [];
        for (const line of root.passwd_file.text().split("\n")) {
            const f = line.split(":");
            const uid = parseInt(f[2]);
            if (f.length < 7 || !(uid >= 1000 && uid < 60000) || /(nologin|false)$/.test(f[6])) continue;
            if (!/^[a-z_][a-z0-9_-]*\$?$/.test(f[0])) continue;
            out.push({ name: f[0], full: f[4] || "" });
        }
        const saved = root.settings.user || "";
        out.sort((a, b) => (b.name === saved) - (a.name === saved));
        return out;
    }

    function pick_user(name) {
        if (root.checking || root.granted || name === root.user || !root.users.some(u => u.name === name)) return;
        if (!root.preview && Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        root.buffer = "";
        root.pending = "";
        root.prompt = "";
        root.failed = false;
        root.fail_count = 0;
        root.message = "";
        root.chosen = name;
    }
    readonly property string skin: root.settings.lock_style || "simple"

    // Settings as an object whose fields are plain strings, with a skin name that can only name a file in lock/skins; else null.
    function parse_settings(text) {
        try {
            const d = JSON.parse(text);
            if (!d || typeof d !== "object" || Array.isArray(d)) return null;
            for (const k of ["user", "lock_style", "lock_tint", "lock_music", "watch_colors", "session", "theme_music", "music_file", "music_volume"]) {
                if (d[k] !== undefined && typeof d[k] !== "string") return null;
            }
            if (d.lock_style !== undefined && !/^[a-z0-9_]+$/.test(d.lock_style)) return null;
            if (d.music_file !== undefined && !/^music\.(ogg|wav|mp3)$/.test(d.music_file)) return null;
            if (d.user !== undefined && !/^[a-z_][a-z0-9_-]*\$?$/.test(d.user)) return null;
            return d;
        } catch (e) {
            return null;
        }
    }

    property string buffer: ""
    property string pending: ""
    property bool checking: false
    property bool failed: false
    property bool granted: false
    property bool caps_lock: false
    property bool typing: false
    property bool saver: false
    property int fail_count: 0
    property string message: ""
    property string prompt: ""
    property int unlock_ms: 0
    property string power_armed: ""

    readonly property var safe_session: ({ name: "Safe Hyprland", exec: "/usr/bin/start-hyprland -- -c /etc/greetd/quickshell/safe-hyprland.lua", safe: true })
    property var sessions: [{ name: "Hyprland", exec: "/usr/bin/start-hyprland" }, root.safe_session]
    property int session_index: 0
    readonly property var session: root.sessions[Math.min(root.session_index, root.sessions.length - 1)]

    function level_setting(text) {
        return Math.max(0, Math.min(1, parseFloat(text || "0.5") || 0));
    }

    readonly property GreeterCtx ctx: GreeterCtx {
        buffer_length: root.buffer.length
        checking: root.checking
        failed: root.failed
        fail_count: root.fail_count
        message: root.message
        prompt: root.prompt
        caps_lock: root.caps_lock
        typing: root.typing
        granted: root.granted
        saver: root.saver && !UPower.onBattery
        user: root.user
        users: root.users
        tint: root.settings.lock_tint || "primary"
        watch_colors: root.settings.watch_colors === "Classic" ? "Classic" : "Theme"
        power_live: !root.preview
        music: root.settings.lock_music !== "off"
        music_volume: root.level_setting(root.settings.music_volume)
        session_name: root.session.name
    }

    Connections {
        target: root.ctx
        function onPower_request(action) { root.power_now(action); }
        function onSession_request() { root.session_index = (root.session_index + 1) % root.sessions.length; }
        function onSafe_request() {
            const i = root.sessions.findIndex(s => s.safe === true);
            if (i >= 0) root.session_index = i;
        }
        function onFallback_request() { root.fallback(); }
        function onUser_request(name) { root.pick_user(name); }
    }

    property bool ready: false

    // Tells the qs-greeter wrapper the UI is up: called once a surface is shown and holds the keyboard.
    function mark_ready() {
        if (root.ready) return;
        root.ready = true;
        if (root.state_dir !== "") ready_file.setText("1\n");
    }

    // Hands the screen to tuigreet: the wrapper sees the marker once qs exits.
    function fallback() {
        if (root.preview) {
            root.message = "Preview: F10 would switch to the text login";
            return;
        }
        fallback_file.setText("1\n");
        quit_timer.start();
    }

    function wake() {
        root.saver = false;
        root.typing = true;
        typing_timer.restart();
        saver_timer.restart();
    }

    function submit() {
        if (root.checking || root.granted || root.buffer === "") return;
        root.failed = false;
        root.message = "";
        const answer = root.buffer;
        root.buffer = "";
        root.checking = true;
        watchdog.restart();
        if (root.preview) {
            root.pending = answer;
            mock_timer.restart();
        } else if (Greetd.state === GreetdState.Authenticating && root.prompt !== "") {
            root.prompt = "";
            Greetd.respond(answer);
        } else {
            // A session left over from an earlier attempt is dropped before a new one starts.
            if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
            root.pending = answer;
            Greetd.createSession(root.user);
        }
    }

    function fail(text) {
        watchdog.stop();
        launch_timer.stop();
        root.granted = false;
        root.checking = false;
        root.pending = "";
        root.prompt = "";
        root.fail_count += 1;
        root.failed = true;
        root.message = text || "Wrong password";
        root.ctx.rejected();
    }

    function accept() {
        watchdog.stop();
        root.checking = false;
        root.pending = "";
        root.prompt = "";
        root.granted = true;
        launch_timer.interval = UPower.onBattery ? 1 : Math.max(1, Math.min(4000, root.unlock_ms));
        launch_timer.restart();
    }

    function launch() {
        const exec = root.session.exec;
        const cmd = exec.startsWith("/usr/bin/start-hyprland") ? "sh -c 'clear; exec " + exec + " >/tmp/hyprland-greetd.log 2>&1'" : exec;
        if (root.preview) {
            console.log("Greeter preview: would launch " + cmd);
            root.granted = false;
            root.fail_count = 0;
            root.message = "Preview: would start " + root.session.name;
            return;
        }
        // greetd runs the joined command through `sh -c "exec ..."`, so it gets one string.
        Greetd.launch([cmd], [], true);
    }

    function power(action) {
        if (root.power_armed !== action) {
            root.power_armed = action;
            root.message = "Press " + (action === "reboot" ? "F11" : "F12") + " again to " + (action === "reboot" ? "reboot" : "power off");
            power_timer.restart();
            return;
        }
        root.power_armed = "";
        root.power_now(action);
    }

    function power_now(action) {
        if (["reboot", "poweroff", "firmware"].indexOf(action) < 0) return;
        if (root.preview) {
            root.message = "Preview: would " + action;
            return;
        }
        if (action === "firmware") Quickshell.execDetached(["systemctl", "reboot", "--firmware-setup"]);
        else Quickshell.execDetached(["systemctl", action]);
    }

    // True when `skin` defines handle_key(event) and it returns exactly true; a throwing skin takes nothing.
    function skin_takes(event, skin) {
        if (!skin || typeof skin.handle_key !== "function") return false;
        try {
            return skin.handle_key(event) === true;
        } catch (e) {
            console.warn("Greeter: skin handle_key failed: " + e);
            return false;
        }
    }

    // `skin` may take a key only while the buffer is empty and greetd waits on nothing.
    function key(event, skin) {
        root.wake();
        if (root.granted) {
            // A fresh press skips the unlock animation; a held Enter from the submit does not.
            if (!event.isAutoRepeat && launch_timer.running) {
                launch_timer.stop();
                root.launch();
            }
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_F10) {
            root.fallback();
            event.accepted = true;
            return;
        }
        if (!root.checking && root.buffer === "" && root.prompt === "" && root.skin_takes(event, skin)) {
            event.accepted = true;
            return;
        }
        const ctrl = (event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier);
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit();
        } else if (event.key === Qt.Key_F2) {
            root.session_index = (root.session_index + 1) % root.sessions.length;
        } else if (event.key === Qt.Key_F11) {
            root.power("reboot");
        } else if (event.key === Qt.Key_F12) {
            root.power("poweroff");
        } else if (root.checking) {
            // Input waits for the answer.
        } else if (event.key === Qt.Key_Escape && root.preview && root.buffer === "") {
            Qt.quit();
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

    Connections {
        target: Greetd
        enabled: !root.preview

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                if (root.pending !== "") {
                    const answer = root.pending;
                    root.pending = "";
                    Greetd.respond(answer);
                } else {
                    watchdog.stop();
                    root.checking = false;
                    root.prompt = message;
                }
            } else if (message !== "") {
                root.message = message;
            }
        }

        function onAuthFailure(message) {
            root.fail(message);
        }

        function onReadyToLaunch() {
            root.accept();
        }

        function onError(error) {
            Greetd.cancelSession();
            root.fail(error);
        }

        function onLaunched() {
            launched_file.setText("1\n");
        }
    }

    Timer {
        id: mock_timer
        interval: 900
        onTriggered: {
            if (root.pending === "wrong") root.fail("Wrong password");
            else root.accept();
        }
    }

    Timer {
        id: watchdog
        interval: 30000
        onTriggered: {
            if (!root.preview) Greetd.cancelSession();
            root.fail("Authentication timed out");
        }
    }

    Timer {
        id: launch_timer
        onTriggered: root.launch()
    }

    Timer {
        id: typing_timer
        interval: 15000
        onTriggered: root.typing = false
    }

    Timer {
        id: saver_timer
        interval: 30000
        running: true
        onTriggered: {
            if (!root.checking && !root.granted && root.buffer === "") root.saver = true;
            else saver_timer.restart();
        }
    }

    Timer {
        id: power_timer
        interval: 4000
        onTriggered: {
            root.power_armed = "";
            root.message = "";
        }
    }

    Timer {
        id: quit_timer
        interval: 200
        onTriggered: Qt.quit()
    }

    FileView {
        id: ready_file
        blockWrites: true
        path: root.state_dir + "/ready"
        printErrors: false
    }

    FileView {
        id: launched_file
        blockWrites: true
        path: root.state_dir + "/launched"
        printErrors: false
    }

    FileView {
        id: fallback_file
        blockWrites: true
        path: root.state_dir + "/fallback"
        printErrors: false
    }

    // Name and Exec of each Wayland session, Hyprland first.
    Process {
        running: true
        command: ["sh", "-c", "for f in /usr/share/wayland-sessions/*.desktop; do n=$(sed -n 's/^Name=//p' \"$f\" | head -n1); e=$(sed -n 's/^Exec=//p' \"$f\" | head -n1); [ -n \"$e\" ] && printf '%s\\t%s\\n' \"$n\" \"$e\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = [];
                for (const line of this.text.split("\n")) {
                    const parts = line.split("\t");
                    if (parts.length === 2 && parts[1] !== "") list.push({ name: parts[0], exec: parts[1] });
                }
                if (list.length === 0) return;
                const preferred = root.settings.session || "Hyprland";
                list.sort((a, b) => (b.name === preferred) - (a.name === preferred));
                list.push(root.safe_session);
                root.sessions = list;
                root.session_index = 0;
            }
        }
    }
}
