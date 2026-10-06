// home/quickshell/.config/quickshell/settings/sections/LockSection.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    footer_hint: "j/k move · H/L change · Enter list · p full view · h/Esc sections · q close"
    rows: [
        {
            label: "Screen",
            values: () => ["follow", "simple"].concat(LockSkins.names),
            text: v => v === "follow" ? "Follow bar style" : v === "simple" ? "Simple" : Style.label(v),
            value: () => Style.lock_style,
            set: v => Style.set_lock_style(v)
        },
        {
            label: "Tint",
            values: () => Style.lock_tints,
            text: v => root.cap(v),
            value: () => Style.lock_tint,
            set: v => Style.set_lock_tint(v)
        },
        {
            label: "Simple backdrop",
            values: () => Style.lock_backdrops,
            text: v => root.cap(v),
            value: () => Style.lock_backdrop,
            set: v => Style.set_lock_backdrop(v)
        },
        {
            label: "Music",
            values: () => ["on", "off"],
            text: v => v,
            value: () => Style.lock_music ? "on" : "off",
            set: v => Style.set_lock_music(v === "on")
        }
    ]

    readonly property string skin: {
        const name = Style.lock_style === "follow" ? Style.saved_name : Style.lock_style;
        return LockSkins.has(name) ? name : "simple";
    }

    onExtra_key: event => {
        if (event.key !== Qt.Key_P || !root.popup || !root.popup.previewer) return;
        root.popup.previewer.open(root.skin, Style.lock_tint);
        event.accepted = true;
    }

    Connections {
        target: root.popup ? root.popup.previewer : null
        function onShownChanged() {
            if (!root.popup.previewer.shown && root.popup.is_open) root.popup.focus_active_view();
        }
    }

    SkinThumb {
        popup: root.popup
        skin: root.skin
        tint: Style.lock_tint
        music: Style.lock_music
        active: root.popup ? root.popup.is_open : false
    }
}
