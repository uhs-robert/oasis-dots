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

    // Opens on `screen` (e.g. "DP-8") with the pane entered, taking no keyboard or pointer input, for looking at a section on a screen nobody is using.
    // Returns false when the screen does not exist. The commands below act on this popup however it was opened.
    // Not "show", which `qs ipc` takes as its own subcommand.
    function view(section: string, screen: string): bool {
        return SettingsNav.show(section, screen);
    }

    // Moves the open pane's row cursor; ignored by panes without one.
    function cursor(index: int): void {
        SettingsNav.command("cursor", index);
    }

    // Steps the selected row's value like H/L (delta -1 or 1). This CHANGES the live setting.
    function step(delta: int): void {
        SettingsNav.command("step", delta);
    }

    // Like Enter on the selected row: opens its list or edit. A list's own choice is not driven from here; use back to close it.
    function activate(): void {
        SettingsNav.command("activate", 0);
    }

    // Closes an open list or edit, else returns from the pane to the sidebar.
    function back(): void {
        SettingsNav.command("back", 0);
    }

    function hide(): void {
        Popups.close();
    }
}
