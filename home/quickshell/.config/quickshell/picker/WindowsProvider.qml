// home/quickshell/.config/quickshell/picker/WindowsProvider.qml
import QtQuick
import "../components"
import "../services"
import "../theme"

// Open windows, most recent first: Enter focuses, or in a move mode sends the window focused at open to the pick's workspace.
PickerProvider {
    id: root

    name: "windows"
    title: root.mode === "focus" ? "Windows" : "Move window to"
    placeholder: root.mode === "focus" ? "Search windows" : root.source_address === "" ? "No focused window to move" : "Search target windows"
    verb: root.mode === "focus" ? "focus" : "move"
    rank_by_usage: false
    keep_order: true
    starts_insert: false
    repeat_steps: true

    // "focus", "move" or "move-silent".
    property string mode: "focus"
    property string source_address: ""

    function propercase(s) {
        return s.length === 0 ? s : s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
    }

    function clean_title(title, short_class) {
        let t = title || "";
        if (short_class.toLowerCase() === "firefox") t = t.replace(/^XXX\s*/, "");
        return t.replace(/\s+[—-]\s+(Mozilla Firefox|Betterbird|Slack|qutebrowser)$/, "");
    }

    function refresh(arg) {
        root.mode = ["move", "move-silent"].indexOf(arg) >= 0 ? arg : "focus";
        root.source_address = WindowState.active_address;
        WindowState.refresh();
        root.rebuild();
        root.initial_index = root.mode === "focus" && root.items.length >= 2 && root.items[0].id === root.source_address ? 1 : 0;
    }

    function rebuild() {
        const list = root.mode === "focus" ? WindowState.windows : WindowState.windows.filter(t => t.address !== root.source_address);
        root.items = list.map(t => {
            const ipc = t.lastIpcObject || {};
            const short = WindowState.short_class(t);
            const ws_name = t.workspace ? t.workspace.name : "";
            const title = root.clean_title(t.title, short);
            return {
                id: t.address,
                label: root.propercase(short || "window"),
                description: ws_name !== "" ? ws_name + " · " + title : title,
                icon_path: WindowState.icon_for(t),
                keywords: [WindowState.class_of(t), ipc.initialClass || "", ws_name, t.title || ""],
                toplevel: t
            };
        });
    }

    function activate(item) {
        if (root.mode === "focus") {
            WindowState.focus(item.id);
            return;
        }
        const ws = item.toplevel ? item.toplevel.workspace : null;
        if (ws && root.source_address !== "") WindowState.move_to_workspace(root.source_address, ws.id, root.mode === "move");
    }

    Connections {
        target: WindowState
        enabled: Pickers.is_open && Pickers.provider === root

        function onWindowsChanged() {
            root.rebuild();
        }
    }

    preview: Component {
        WindowThumbnail {
            property var entry: null
            toplevel: entry ? entry.toplevel : null
            icon_size: Style.px(64)
        }
    }
}
