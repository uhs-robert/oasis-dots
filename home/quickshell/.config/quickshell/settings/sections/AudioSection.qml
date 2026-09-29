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
            label: "Volume",
            values: () => ThemeAudio.volumes,
            text: v => Math.round(v * 100) + "%",
            value: () => ThemeAudio.volume,
            set: v => ThemeAudio.set_volume(v)
        },
        {
            label: "Sound pack",
            values: () => ThemeAudio.packs,
            text: v => v === "follow" ? "Follow style (" + Style.label(Style.saved_name) + ")" : Style.label(v),
            value: () => ThemeAudio.pack,
            set: v => ThemeAudio.set_pack(v)
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
        text: "Your own wav/ogg files in ~/.local/share/quickshell/sounds/<style>/ (cursor, confirm, cancel, notify, music) replace the shipped ones. Lock music also needs the Lock screen's Music on."
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
