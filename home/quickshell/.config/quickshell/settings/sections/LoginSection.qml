// home/quickshell/.config/quickshell/settings/sections/LoginSection.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    rows: [
        {
            label: "Sync to greeter",
            desc: "Keep the login screen in step with these choices. Off leaves it as it is.",
            values: () => ["on", "off"],
            text: v => v,
            value: () => LoginScreen.sync ? "on" : "off",
            set: v => LoginScreen.set_sync(v === "on")
        },
        {
            label: "Screen",
            desc: "The login design. Follow lock screen uses the Lock screen setting.",
            values: () => ["follow", "simple"].concat(LockSkins.names),
            text: v => v === "follow" ? "Follow lock screen" : v === "simple" ? "Simple" : Style.label(v),
            value: () => LoginScreen.screen,
            set: v => LoginScreen.set_screen(v)
        },
        {
            label: "Tint",
            desc: "Recolors the skin. Follow lock screen uses the Lock screen tint.",
            values: () => ["follow"].concat(Style.lock_tints),
            text: v => v === "follow" ? "Follow lock screen" : root.cap(v),
            value: () => LoginScreen.tint,
            set: v => LoginScreen.set_tint(v)
        },
        {
            label: "Music",
            desc: "Play your own music file at login. Follow lock screen uses the lock's Music.",
            values: () => LoginScreen.musics,
            text: v => v === "follow" ? "Follow lock screen" : v,
            value: () => LoginScreen.music,
            set: v => LoginScreen.set_music(v)
        },
        {
            label: "Session",
            desc: "The Wayland session the login screen starts, from the installed sessions.",
            values: () => LoginScreen.sessions,
            text: v => v,
            value: () => LoginScreen.session,
            set: v => LoginScreen.set_session(v)
        }
    ]

    SkinThumb {
        popup: root.popup
        skin: LoginScreen.resolved_screen
        tint: LoginScreen.resolved_tint
        music: LoginScreen.resolved_music
        login: true
        active: root.popup ? root.popup.is_open : false
    }

    footer: Text {
        Layout.fillWidth: true
        visible: !LoginScreen.installed
        text: "Greeter not installed: run just greeter-sync --install"
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
