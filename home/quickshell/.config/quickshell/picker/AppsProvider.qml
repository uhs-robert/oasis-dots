// home/quickshell/.config/quickshell/picker/AppsProvider.qml
import QtQuick
import Quickshell
import "../services"

PickerProvider {
    id: root

    name: "apps"
    title: "Apps"
    placeholder: "Search apps"
    columns: 4

    function icon_path(icon) {
        if (!icon) return Quickshell.iconPath("application-x-executable", true);
        if (icon.startsWith("/")) return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }

    function rebuild() {
        root.items = DesktopEntries.applications.values.filter(e => !e.noDisplay).map(e => ({
            id: e.id,
            label: e.name,
            description: e.comment !== "" ? e.comment : e.genericName,
            icon: e.icon,
            icon_path: root.icon_path(e.icon),
            keywords: [e.genericName].concat(Array.from(e.keywords), Array.from(e.categories)),
            entry: e
        }));
    }

    function activate(item) {
        const e = item.entry;
        if (!e) return;
        if (e.runInTerminal) {
            const context = { command: [Quickshell.env("HOME") + "/.config/hypr/scripts/term", "-e"].concat(Array.from(e.command)) };
            if (e.workingDirectory !== "") context.workingDirectory = e.workingDirectory;
            Quickshell.execDetached(context);
        } else {
            e.execute();
        }
    }

    // Built once after startup and again only when desktop files change, so opening costs nothing.
    Component.onCompleted: Qt.callLater(root.rebuild)

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            Qt.callLater(root.rebuild);
        }
    }
}
