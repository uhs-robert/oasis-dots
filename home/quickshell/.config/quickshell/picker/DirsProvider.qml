// home/quickshell/.config/quickshell/picker/DirsProvider.qml
import QtQuick
import Quickshell
import Quickshell.Io
import "../services"
import "../theme"

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
    readonly property var term: ["sh", "-c", "t=~/.config/hypr/scripts/term; [ -x \"$t\" ] || t=\"${TERMINAL:-kitty}\"; exec \"$t\" \"$@\"", "sh"]
    property string file_manager_class: DefaultApps.app_value("tui_file_manager") || "yazi"
    readonly property string open_script: "s=${SHELL:-sh}; cd \"$1\" || exit; fm=$2; if [ \"$fm\" = yazi ] && \"$s\" -i -c 'type y' >/dev/null 2>&1; then fm=y; fi; exec \"$s\" -i -c \"$fm; exec \\\"$s\\\" -i\""
    readonly property string shell_script: "s=${SHELL:-sh}; cd \"$1\" || exit; exec \"$s\" -i"

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
        root.file_manager_class = arg || DefaultApps.app_value("tui_file_manager") || "yazi";
        list_proc.running = false;
        list_proc.running = true;
    }

    function activate(item) {
        Quickshell.execDetached(root.term.concat(["--class", root.file_manager_class, "-e", "sh", "-c", root.open_script, "sh", item.path, root.file_manager_class]));
    }

    function run_action(key, item) {
        if (key !== "t") return;
        Pickers.close();
        Quickshell.execDetached(root.term.concat(["-e", "sh", "-c", root.shell_script, "sh", item.path]));
    }

    Process {
        id: list_proc
        command: ["zoxide", "query", "-ls"]
        stdout: StdioCollector {
            onStreamFinished: root.items = root.parse(text)
        }
    }

    preview: Component {
        Item {
            id: pane
            property var entry: null
            property var rows: []
            property string phase: "loading"
            property string shown_path: ""
            readonly property int row_h: Math.ceil(Style.fs(-3) * 1.6)
            readonly property int fit: Math.max(1, Math.floor((pane.height - 20 - pane.row_h * 2) / pane.row_h))
            readonly property bool cut: pane.rows.length > pane.fit
            readonly property var lines: pane.cut ? pane.rows.slice(0, pane.fit - 1) : pane.rows

            clip: true
            onEntryChanged: {
                pane.phase = "loading";
                pane.rows = [];
                debounce.restart();
            }

            function parse(text, path) {
                if (text.startsWith("\x01")) return pane.set_state("missing", path);
                if (text.endsWith("\x02")) return pane.set_state("unreadable", path);
                const dirs = [], files = [], hdirs = [], hfiles = [];
                for (const name of text.split("\n")) {
                    if (name === "") continue;
                    const is_dir = name.endsWith("/");
                    const hidden = name.startsWith(".");
                    const row = { name: name, dir: is_dir, hidden: hidden };
                    (hidden ? (is_dir ? hdirs : hfiles) : (is_dir ? dirs : files)).push(row);
                }
                pane.rows = dirs.concat(files, hdirs, hfiles);
                pane.phase = pane.rows.length > 0 ? "ready" : "empty";
                pane.shown_path = path;
            }

            function set_state(phase, path) {
                pane.rows = [];
                pane.phase = phase;
                pane.shown_path = path;
            }

            Timer {
                id: debounce
                interval: 100
                onTriggered: {
                    dir_proc.running = false;
                    if (!pane.entry) return;
                    dir_proc.path = pane.entry.path;
                    dir_proc.running = true;
                }
            }

            Process {
                id: dir_proc
                property string path: ""
                command: ["sh", "-c", "printf '%s\\n' \"$1\"; cd \"$1\" 2>/dev/null || { printf '\\001'; exit; }; ls -A -p --group-directories-first 2>/dev/null || printf '\\002'", "sh", dir_proc.path]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const nl = text.indexOf("\n");
                        const path = text.slice(0, nl);
                        if (nl >= 0 && pane.entry && path === pane.entry.path) pane.parse(text.slice(nl + 1), path);
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Style.radius(4)
                color: Style.pal.bg_surface
            }

            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 0

                Text {
                    width: parent.width
                    height: pane.row_h * 2
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                    text: pane.entry ? pane.entry.label : ""
                    color: Style.text_accent
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }

                Text {
                    visible: pane.phase !== "ready"
                    width: parent.width
                    height: pane.row_h
                    text: pane.phase === "missing" ? "Not found" : pane.phase === "unreadable" ? "Can't read" : pane.phase === "empty" ? "Empty" : ""
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }

                Repeater {
                    model: pane.lines

                    Row {
                        id: line
                        required property var modelData
                        width: pane.width - 20
                        height: pane.row_h
                        spacing: 6
                        opacity: line.modelData.hidden ? 0.55 : 1

                        Text {
                            width: Style.px(16)
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: line.modelData.dir ? "\uf07b" : "\uf15b"
                            color: line.modelData.dir ? Style.text_accent : Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                        }

                        Text {
                            width: parent.width - Style.px(22)
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: line.modelData.dir ? line.modelData.name.slice(0, -1) : line.modelData.name
                            color: Style.text_fg
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                        }
                    }
                }

                Text {
                    visible: pane.cut
                    height: pane.row_h
                    text: "+" + (pane.rows.length - pane.lines.length) + " more"
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }
            }
        }
    }
}
