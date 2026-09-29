// home/quickshell/.config/quickshell/picker/DirsProvider.qml
import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

// zoxide directories in zoxide's own order: Enter opens the file manager there, `t` a shell.
PickerProvider {
    id: root

    name: "dirs"
    title: "Directories"
    placeholder: "Search directories"
    rank_by_usage: false
    keep_order: true
    actions: [{ key: "t", desc: "shell" }]

    readonly property string home: Quickshell.env("HOME")
    readonly property string term: root.home + "/.config/hypr/scripts/term"
    property string file_manager_class: "yazi"

    function parse(text) {
        const out = [];
        for (const line of text.split("\n")) {
            const m = /^\s*([\d.]+)\s+(.+)$/.exec(line);
            if (!m) continue;
            const path = m[2];
            const shown = path === root.home ? "~" : path.startsWith(root.home + "/") ? "~" + path.slice(root.home.length) : path;
            out.push({ id: path, label: shown, description: m[1], icon: "folder", path: path });
        }
        return out;
    }

    // The mode arg carries Config.app.tui_file_manager as the window class.
    function refresh(arg) {
        root.file_manager_class = arg || "yazi";
        list_proc.running = false;
        list_proc.running = true;
    }

    function activate(item) {
        Quickshell.execDetached([root.term, "--class", root.file_manager_class, "-e", "zsh", "-i", "-c", "cd \"$1\" && y; exec zsh -i", "zsh", item.path]);
    }

    function run_action(key, item) {
        if (key !== "t") return;
        Pickers.close();
        Quickshell.execDetached([root.term, "-e", "zsh", "-i", "-c", "cd \"$1\" && exec zsh -i", "zsh", item.path]);
    }

    Process {
        id: list_proc
        command: ["zoxide", "query", "-ls"]
        stdout: StdioCollector {
            onStreamFinished: root.items = root.parse(text)
        }
    }
}
