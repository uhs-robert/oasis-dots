// home/quickshell/.config/quickshell/settings/sections/AudioSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    footer_hint: "j/k move · h/l change · p test sounds · Esc sections · q close"
    rows: [
        {
            label: "Interface sounds",
            values: () => ["on", "off"],
            text: v => v,
            value: () => ThemeAudio.ui ? "on" : "off",
            set: v => ThemeAudio.set_flag("ui", v === "on")
        },
        {
            label: "Notification sound",
            values: () => ["on", "off"],
            text: v => v,
            value: () => ThemeAudio.notify ? "on" : "off",
            set: v => ThemeAudio.set_flag("notify", v === "on")
        },
        {
            label: "Lock music",
            values: () => ["on", "off"],
            text: v => v,
            value: () => ThemeAudio.music ? "on" : "off",
            set: v => ThemeAudio.set_flag("music", v === "on")
        },
        {
            label: "Music volume",
            values: () => ThemeAudio.volumes,
            text: v => Math.round(v * 100) + "%",
            value: () => ThemeAudio.music_volume,
            set: v => ThemeAudio.set_volume("music_volume", v)
        },
        {
            label: "Effects volume",
            values: () => ThemeAudio.volumes,
            text: v => Math.round(v * 100) + "%",
            value: () => ThemeAudio.fx_volume,
            set: v => ThemeAudio.set_volume("fx_volume", v)
        },
        {
            label: "Effects pack",
            values: () => ThemeAudio.pack_options(Style.saved_name),
            text: v => ThemeAudio.pack_label(v) + (v === Style.saved_name ? " (own)" : "") + (v === ThemeAudio.default_pack(Style.saved_name) ? " (default)" : ""),
            value: () => ThemeAudio.pack_for(Style.saved_name),
            set: v => ThemeAudio.set_pack(Style.saved_name, v)
        }
    ]

    onExtra_key: event => {
        if (event.key !== Qt.Key_P) return;
        ThemeAudio.preview("cursor");
        preview_timer.step = 0;
        preview_timer.restart();
        event.accepted = true;
    }

    Timer {
        id: preview_timer
        property int step: 0
        readonly property var order: ["confirm", "cancel", "notify"]
        interval: 450
        repeat: true
        onTriggered: {
            if (preview_timer.step >= preview_timer.order.length) {
                preview_timer.stop();
                return;
            }
            ThemeAudio.preview(preview_timer.order[preview_timer.step]);
            preview_timer.step += 1;
        }
    }

    footer: Text {
        Layout.fillWidth: true
        text: "Effects packs are set per style; imported game packs appear once imported. Your own wav/ogg files in ~/.local/share/quickshell/sounds/<style>/ (cursor, confirm, cancel, notify) replace the pack's. Lock and login music only plays from your own music.ogg/wav/mp3 there, with the Lock screen's Music on."
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
