import QtQuick
import Quickshell
import Quickshell.Io
import "Projects.js" as Projects

// tmuxifier layouts, a dot on those whose session runs. Enter hands the layout to tmux-layout, which focuses its
// terminal or loads it in a new one.
PickerProvider {
    id: root

    name: "projects"
    title: "Projects"
    placeholder: "Search projects"
    empty_text: "No tmuxifier layouts in " + root.layout_dir

    readonly property string layout_dir: Quickshell.env("TMUXIFIER_LAYOUT_PATH") || "~/.tmuxifier/layouts"
    readonly property string layout_script: Quickshell.env("HOME") + "/.config/hypr/scripts/tmux-layout"

    function refresh(arg) {
        list_proc.running = false;
        list_proc.running = true;
    }

    function activate(item) {
        Quickshell.execDetached([root.layout_script, item.stem]);
    }

    Process {
        id: list_proc
        command: ["sh", "-c", Projects.list_script]
        stdout: StdioCollector {
            onStreamFinished: root.items = Projects.items_of(Projects.parse_listing(text))
        }
    }
}
