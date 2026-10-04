// home/quickshell/.config/quickshell/settings/sections/DefaultAppsSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    rows: DefaultApps.app_keys.map(c => ({
                label: c.label,
                values: () => DefaultApps.app_choices(c.key),
                text: v => v === "" ? "Machine default" : v,
                value: () => DefaultApps.app_value(c.key),
                set: v => DefaultApps.set_app(c.key, v)
            })).concat(DefaultApps.mime_keys.map(c => ({
                label: c.label,
                values: () => DefaultApps.mime_choices(c.key),
                text: v => DefaultApps.mime_text(c.key, v),
                value: () => DefaultApps.mime_value(c.key),
                set: v => DefaultApps.set_mime(c.key, v)
            })))

    Component.onCompleted: DefaultApps.refresh()

    footer: Text {
        Layout.fillWidth: true
        text: "Terminal, editor and file managers reload Hyprland when changed. Saved to " + DefaultApps.state_dir + "/apps.json"
        wrapMode: Text.WordWrap
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
