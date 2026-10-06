// home/quickshell/.config/quickshell/settings/sections/InputSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    readonly property var modes: ({ insert: "INSERT", normal: "NORMAL" })

    rows: [{
        label: "Start typing in",
        values: () => InputSettings.choices.start_mode,
        text: v => root.modes[v] || String(v),
        value: () => InputSettings.values.start_mode,
        set: v => InputSettings.set("start_mode", v)
    }]

    footer: Text {
        Layout.fillWidth: true
        text: "The mode pickers, settings lists and search popups open in; from NORMAL, i or / starts typing. The HyprVim prompt always opens in INSERT. Saved to " + InputSettings.state_dir + "/input.json"
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
