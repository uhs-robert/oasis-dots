// home/quickshell/.config/quickshell/lock/LockPreview.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../theme"
import "../services"

// A lock skin in a plain overlay window with fake auth state; never touches the session lock or PAM.
Scope {
    id: root

    property bool shown: false
    property string skin: ""
    property string held_screen_name: ""

    // `name` is a style, or "" for the lock's own; returns "ok" or "unknown".
    function open(name) {
        const style_name = name === "" || name === "follow" ? Style.lock_name : name;
        if (style_name !== "simple" && !(style_name in Style.styles)) return "unknown";
        const mon = Hyprland.focusedMonitor;
        root.held_screen_name = mon ? mon.name : "";
        root.skin = style_name;
        root.reset();
        root.shown = true;
        root.load();
        return "ok";
    }

    function close() {
        replay.stop();
        root.shown = false;
        loader.source = "";
    }

    function reset() {
        fake.forced_phase = "";
        fake.buffer_length = 0;
        fake.checking = false;
        fake.failed = false;
        fake.fail_count = 0;
        fake.message = "";
        fake.granted = false;
        fake.saver = false;
    }

    function load() {
        if (root.skin === "simple") {
            loader.setSource(Qt.resolvedUrl("LockScreen.qml"), { ctx: fake });
            return;
        }
        const file = root.skin.charAt(0).toUpperCase() + root.skin.slice(1) + ".qml";
        loader.setSource(Qt.resolvedUrl("skins/" + file), { ctx: fake });
        if (loader.status === Loader.Error) loader.setSource(Qt.resolvedUrl("LockScreen.qml"), { ctx: fake });
    }

    // Each phase starts from a fresh skin, so an unlock's collapsed tube never carries over.
    function phase(p) {
        replay.stop();
        root.reset();
        if (p === "typing") fake.buffer_length = 3;
        else if (p === "saver") fake.saver = true;
        else if (p === "wrong" || p === "unlock") fake.forced_phase = p;
        root.load();
        fake.forced_phase = "";
        if (p === "wrong") root.fake_fail();
        else if (p === "unlock") root.fake_unlock();
    }

    function fake_fail() {
        fake.buffer_length = 0;
        fake.fail_count += 1;
        fake.message = "Wrong password";
        fake.failed = true;
        fake.rejected();
    }

    function fake_unlock() {
        fake.buffer_length = 0;
        fake.granted = true;
        const ms = loader.item && typeof loader.item.unlock_ms === "number" ? loader.item.unlock_ms : 0;
        replay.interval = ms + 900;
        replay.restart();
    }

    LockCtx {
        id: fake
        typing: true
    }

    Timer {
        id: replay
        onTriggered: {
            root.reset();
            root.load();
        }
    }

    PanelWindow {
        visible: root.shown
        screen: Quickshell.screens.find(s => s.name === root.held_screen_name) || null
        color: Theme.bg_shadow
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell-lock-preview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Item {
            anchors.fill: parent
            focus: true

            // Esc or q closes; 1-5 pick idle, typing, wrong, unlock, saver; other keys type, Enter fails, Shift+Enter unlocks.
            Keys.onPressed: event => {
                const phases = { "1": "idle", "2": "typing", "3": "wrong", "4": "unlock", "5": "saver" };
                if (event.key === Qt.Key_Escape || event.text === "q") root.close();
                else if (event.text in phases) root.phase(phases[event.text]);
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (event.modifiers & Qt.ShiftModifier) root.fake_unlock();
                    else root.fake_fail();
                } else if (event.key === Qt.Key_Backspace) fake.buffer_length = Math.max(0, fake.buffer_length - 1);
                else if (event.text !== "") {
                    fake.saver = false;
                    fake.failed = false;
                    fake.buffer_length += 1;
                } else return;
                event.accepted = true;
            }

            Loader {
                id: loader
                anchors.fill: parent
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: root.close()
            }
        }
    }
}
