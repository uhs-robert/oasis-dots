// home/quickshell/.config/quickshell/settings/sections/DefaultAppsSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    readonly property var notes: ({
            term: "Terminal that Hyprland binds and terminal programs open in. Reloads Hyprland when changed.",
            editor: "Editor that Hyprland binds launch. Reloads Hyprland when changed.",
            gui_file_manager: "Graphical file manager its Hyprland bind opens. Reloads Hyprland when changed.",
            tui_file_manager: "Terminal file manager, such as yazi, run in your terminal. Reloads Hyprland when changed.",
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
}
