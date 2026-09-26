// /etc/greetd/quickshell/GreeterSurface.qml
import QtQuick
import "theme"

// One screen of the greeter: the lock skin for the saved lock style, else the simple screen, with the session and power keys under it.
Item {
    id: root

    // Keys live here, not in the skin, so a broken skin still takes the password.
    focus: true
    Keys.onPressed: event => Greeter.key(event)
    onActiveFocusChanged: if (root.activeFocus && root.visible) Greeter.mark_ready()
    onVisibleChanged: if (root.activeFocus && root.visible) Greeter.mark_ready()

    Rectangle {
        anchors.fill: parent
        color: Theme.bg_shadow
    }

    Loader {
        id: skin_loader
        anchors.fill: parent

        Component.onCompleted: {
            const name = Greeter.skin;
            if (name !== "simple") skin_loader.setSource(Qt.resolvedUrl("lock/skins/" + name.charAt(0).toUpperCase() + name.slice(1) + ".qml"), { ctx: Greeter.ctx });
            if (name === "simple" || skin_loader.status === Loader.Error) skin_loader.setSource(Qt.resolvedUrl("GreeterSimple.qml"), { ctx: Greeter.ctx });
            const ms = skin_loader.item ? skin_loader.item.unlock_ms : undefined;
            Greeter.unlock_ms = typeof ms === "number" ? ms : 0;
        }
    }

    Text {
        visible: skin_loader.status === Loader.Error
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: Greeter.checking ? "Checking" : "Log in as " + Greeter.user + ": type your password and press Enter. " + "*".repeat(Greeter.buffer.length) + (Greeter.failed ? "\n" + Greeter.message : "")
        color: Greeter.failed ? Theme.error : Theme.fg_core
        font.pixelSize: 20
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.max(2, parent.height * 0.004)
        text: (Greeter.preview ? "PREVIEW · " : "") + "F2 " + Greeter.session.name + "   F10 or SUPER+T text login   F11 reboot   F12 power off"
        color: Theme.fg_dim
        font.family: "Share Tech Mono"
        font.pixelSize: Math.max(11, parent.height * 0.014)
    }
}
