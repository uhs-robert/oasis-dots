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
            values: () => ["on", "off"],
            text: v => v,
            value: () => LoginScreen.sync ? "on" : "off",
            set: v => LoginScreen.set_sync(v === "on")
        },
        {
            label: "Screen",
            values: () => ["follow", "simple"].concat(LockSkins.names),
            text: v => v === "follow" ? "Follow lock screen" : v === "simple" ? "Simple" : Style.label(v),
            value: () => LoginScreen.screen,
            set: v => LoginScreen.set_screen(v)
        },
        {
            label: "Tint",
            values: () => ["follow"].concat(Style.lock_tints),
            text: v => v === "follow" ? "Follow lock screen" : root.cap(v),
            value: () => LoginScreen.tint,
            set: v => LoginScreen.set_tint(v)
        },
        {
            label: "Music",
            values: () => LoginScreen.musics,
            text: v => v === "follow" ? "Follow lock screen" : v,
            value: () => LoginScreen.music,
            set: v => LoginScreen.set_music(v)
        },
        {
            label: "Session",
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
        text: LoginScreen.installed ? "Saved to " + LoginScreen.data_dir : "Greeter not installed: run just greeter-sync --install"
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
