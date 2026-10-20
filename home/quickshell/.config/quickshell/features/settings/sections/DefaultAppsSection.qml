import QtQuick
import QtQuick.Layouts
import qs.features.settings

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

    rows: DefaultAppsSettings.app_keys.map(c => ({
                label: c.label,
                desc: root.notes[c.key],
                values: () => DefaultAppsSettings.app_choices(c.key),
                text: v => v === "" ? "Machine default" : v,
                value: () => DefaultAppsSettings.app_value(c.key),
                set: v => DefaultAppsSettings.set_app(c.key, v)
            })).concat(DefaultAppsSettings.mime_keys.map(c => ({
                label: c.label,
                desc: root.notes[c.key],
                values: () => DefaultAppsSettings.mime_choices(c.key),
                text: v => DefaultAppsSettings.mime_text(c.key, v),
                value: () => DefaultAppsSettings.mime_value(c.key),
                set: v => DefaultAppsSettings.set_mime(c.key, v)
            })))

    Component.onCompleted: DefaultAppsSettings.refresh()
}
