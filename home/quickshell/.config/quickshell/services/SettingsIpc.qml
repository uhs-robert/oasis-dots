// home/quickshell/.config/quickshell/services/SettingsIpc.qml
import Quickshell.Io

IpcHandler {
    target: "settings"

    // A section id from settings/Sections.js, or "" for the last one shown.
    function open(section: string): void {
        SettingsNav.open(section);
    }

    function toggle(): void {
        Popups.toggle("settings", undefined);
    }
}
