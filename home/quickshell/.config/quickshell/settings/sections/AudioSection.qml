// home/quickshell/.config/quickshell/settings/sections/AudioSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    Component.onCompleted: ThemeAudio.settings_open += 1
    Component.onDestruction: ThemeAudio.settings_open -= 1

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
            values: () => ThemeAudio.pack_options(),
            text: v => v === "" ? "Follow style (" + ThemeAudio.pack_label(ThemeAudio.default_pack(Style.saved_name)) + ")" : ThemeAudio.pack_label(v),
            value: () => ThemeAudio.valid_pack(ThemeAudio.choice) ? ThemeAudio.choice : "",
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
        readonly property var order: ["confirm", "cancel", "notify", "error", "lock", "unlock"]
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
        text: "The effects pack applies to every style; Follow style uses each style's own. Imported game packs appear once imported. Your own wav/ogg files in ~/.local/share/quickshell/sounds/<pack>/ (cursor, confirm, cancel, notify) replace that pack's. Lock and login music only plays from your own music.ogg/wav/mp3 there, with the Lock screen's Music on."
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
