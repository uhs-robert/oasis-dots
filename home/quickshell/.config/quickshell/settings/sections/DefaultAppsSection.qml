// home/quickshell/.config/quickshell/settings/sections/DefaultAppsSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    readonly property var notes: ({
            term: "Terminal that Hyprland binds and terminal programs open in. Machine default keeps the config's.",
            editor: "Editor that Hyprland binds launch. Machine default keeps the config's.",
            gui_file_manager: "Graphical file manager that its Hyprland bind opens.",
            tui_file_manager: "Terminal file manager, such as yazi, opened in your terminal.",
            web: "Opens web links and pages.",
            mail: "Opens mailto links and mail.",
            pdf: "Opens PDF files.",
            images: "Opens image files.",
            video: "Opens video files.",
            audio: "Opens audio files.",
            text: "Opens plain text files.",
            directories: "Opens folders, including Wallpaper's o key."
        })

    rows: DefaultApps.app_keys.map(c => ({
                label: c.label,
                desc: root.notes[c.key],
                values: () => DefaultApps.app_choices(c.key),
                text: v => v === "" ? "Machine default" : v,
                value: () => DefaultApps.app_value(c.key),
                set: v => DefaultApps.set_app(c.key, v)
            })).concat(DefaultApps.mime_keys.map(c => ({
                label: c.label,
                desc: root.notes[c.key],
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
