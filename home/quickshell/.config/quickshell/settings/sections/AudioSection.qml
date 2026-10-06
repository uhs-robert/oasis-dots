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

    section_keys: "p test sounds"
    footer_hint: "j/k move · H/L change · p test sounds · h/Esc sections · q close"
    rows: [
        {
            label: "Interface sounds",
            desc: "Play the pack's cursor, confirm and cancel sounds as you move around the shell.",
            values: () => ["on", "off"],
            text: v => v,
            value: () => ThemeAudio.ui ? "on" : "off",
            set: v => ThemeAudio.set_flag("ui", v === "on")
        },
        {
            label: "Notification sound",
            desc: "Play the pack's notify sound when a notification arrives.",
            values: () => ["on", "off"],
            text: v => v,
            value: () => ThemeAudio.notify ? "on" : "off",
            set: v => ThemeAudio.set_flag("notify", v === "on")
        },
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
        },
        {
            label: "Effects volume",
            desc: "Volume of interface and notification sounds.",
            values: () => ThemeAudio.volumes,
            text: v => Math.round(v * 100) + "%",
            value: () => ThemeAudio.fx_volume,
            set: v => ThemeAudio.set_volume("fx_volume", v)
        },
        {
            label: "Effects pack",
            desc: "Sound set for every style; Follow style uses its own. Your wav/ogg files in sounds/<pack>/ replace a pack's.",
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
}
