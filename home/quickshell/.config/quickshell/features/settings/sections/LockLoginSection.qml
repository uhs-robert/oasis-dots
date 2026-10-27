import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.features.lock
import qs.features.audio
import qs.features.settings

RowsSection {
    id: root

    readonly property bool on_login: root.cursor_heading === "Login"

    section_keys: "p full view"
    footer_hint: "j/k move · " + root.layout_hint + "H/L change · Enter list · p full view · h/Esc sections · q close"
    rows: [
        { heading: "Lock" },
        {
            label: "Screen",
            desc: "The lock design. Follow bar style uses the current style's skin; Simple is a plain card.",
            values: () => ["follow", "simple"].concat(LockSkins.names),
            text: v => v === "follow" ? "Follow bar style" : v === "simple" ? "Simple" : Style.label(v),
            value: () => Style.lock_style,
            set: v => Style.set_lock_style(v)
        },
        {
            label: "Tint",
            desc: "Recolors the skin. Classic keeps each skin's original colours. Skins with a fixed game palette ignore it.",
            values: () => Style.lock_tints,
            text: v => root.cap(v),
            value: () => Style.lock_tint,
            set: v => Style.set_lock_tint(v)
        },
        {
            label: "Simple backdrop",
            desc: "What the Simple screen shows behind its card: a pixelated or blurred desktop, or nothing.",
            values: () => Style.lock_backdrops,
            text: v => root.cap(v),
            value: () => Style.lock_backdrop,
            set: v => Style.set_lock_backdrop(v)
        },
        {
            label: "Music",
            desc: "Play your own music file while locked. Needs Lock music (under Music) on too.",
            values: () => ["on", "off"],
            text: v => v,
            value: () => Style.lock_music ? "on" : "off",
            set: v => Style.set_lock_music(v === "on")
        },
        { heading: "Login" },
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
            desc: "The login design. Follow lock screen uses the lock's Screen.",
            values: () => ["follow", "simple"].concat(LockSkins.names),
            text: v => v === "follow" ? "Follow lock screen" : v === "simple" ? "Simple" : Style.label(v),
            value: () => LoginSettings.screen,
            set: v => LoginSettings.set_screen(v)
        },
        {
            label: "Tint",
            desc: "Recolors the skin. Follow lock screen uses the lock's Tint.",
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
        },
        { heading: "Music" },
        {
            label: "Lock music",
            desc: "Plays your music.ogg/wav/mp3 from ~/.local/share/quickshell/sounds/<pack>/ at lock and login.",
            values: () => ["on", "off"],
            text: v => v,
            value: () => ThemeAudio.music ? "on" : "off",
            set: v => ThemeAudio.set_flag("music", v === "on")
        },
        {
            label: "Music volume",
            desc: "Volume of the lock and login music.",
            values: () => ThemeAudio.volumes,
            text: v => Math.round(v * 100) + "%",
            value: () => ThemeAudio.music_volume,
            set: v => ThemeAudio.set_volume("music_volume", v)
        }
    ]

    readonly property string lock_skin: {
        const name = Style.lock_style === "follow" ? Style.saved_name : Style.lock_style;
        return LockSkins.has(name) ? name : "simple";
    }

    onExtra_key: event => {
        if (event.key !== Qt.Key_P || !root.popup || !root.popup.previewer) return;
        if (root.on_login) root.popup.previewer.open(LoginSettings.resolved_screen, LoginSettings.resolved_tint);
        else root.popup.previewer.open(root.lock_skin, Style.lock_tint);
        event.accepted = true;
    }

    Connections {
        target: root.popup ? root.popup.previewer : null
        function onShownChanged() {
            if (!root.popup.previewer.shown && root.popup.is_open) root.popup.focus_active_view();
        }
    }

    // The Login rows show the login screen, the others the lock screen. Kept to its old size, so the rows below stay in view.
    SkinThumb {
        Layout.fillWidth: false
        Layout.preferredWidth: Math.min(root.width, Style.px(640))
        popup: root.popup
        skin: root.on_login ? LoginSettings.resolved_screen : root.lock_skin
        tint: root.on_login ? LoginSettings.resolved_tint : Style.lock_tint
        music: root.on_login ? LoginSettings.resolved_music : Style.lock_music
        login: root.on_login
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
