import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.features.lock
import qs.features.settings

RowsSection {
    id: root

    rows: [
        {
            label: "Sync to greeter",
            desc: "Keep the login screen in step with these choices. Off leaves it as it is.",
            values: () => ["on", "off"],
            text: v => v,
            value: () => LoginSettings.sync ? "on" : "off",
            set: v => LoginSettings.set_sync(v === "on")
        },
        {
            label: "Screen",
            desc: "The login design. Follow lock screen uses the Lock screen setting.",
            values: () => ["follow", "simple"].concat(LockSkins.names),
            text: v => v === "follow" ? "Follow lock screen" : v === "simple" ? "Simple" : Style.label(v),
            value: () => LoginSettings.screen,
            set: v => LoginSettings.set_screen(v)
        },
        {
            label: "Tint",
            desc: "Recolors the skin. Follow lock screen uses the Lock screen tint.",
            values: () => ["follow"].concat(Style.lock_tints),
            text: v => v === "follow" ? "Follow lock screen" : root.cap(v),
            value: () => LoginSettings.tint,
            set: v => LoginSettings.set_tint(v)
        },
        {
            label: "Music",
            desc: "Play your own music file at login. Follow lock screen uses the lock's Music.",
            values: () => LoginSettings.musics,
            text: v => v === "follow" ? "Follow lock screen" : v,
            value: () => LoginSettings.music,
            set: v => LoginSettings.set_music(v)
        },
        {
            label: "Session",
            desc: "The Wayland session the login screen starts, from the installed sessions.",
            values: () => LoginSettings.sessions,
            text: v => v,
            value: () => LoginSettings.session,
            set: v => LoginSettings.set_session(v)
        }
    ]

    SkinThumb {
        popup: root.popup
        skin: LoginSettings.resolved_screen
        tint: LoginSettings.resolved_tint
        music: LoginSettings.resolved_music
        login: true
        active: root.popup ? root.popup.is_open : false
    }

    footer: Text {
        Layout.fillWidth: true
        visible: !LoginSettings.installed
        text: "Greeter not installed: run just greeter-sync --install"
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
