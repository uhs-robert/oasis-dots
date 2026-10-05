// home/quickshell/.config/quickshell/services/Palettes.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The Oasis palettes Hyprland's theme switcher knows, the active one, and applying a choice through that switcher.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string state_dir: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg && xdg !== "" ? xdg : root.home + "/.local/state") + "/hypr";
    }
    readonly property string switch_script: root.home + "/.config/hypr/theme/switch.lua"
    // Palette name to { key: "#hex" }.
    property var colors: ({})
    readonly property var names: Object.keys(root.colors)
    property string current: ""
    // Settings > Colors > Sync Neovim; theme/generate/nvim.lua reads the same flag file.
    property bool nvim_sync: false
    // True once the palette list and the active name have both been read.
    property bool settled: false
    readonly property bool ready: root.settled && root.names.length > 0
    readonly property var swatch_keys: ["bg_core", "bg_surface", "fg_core", "theme_primary", "theme_secondary", "theme_accent", "green", "red", "blue", "magenta"]

    function label(name) {
        const base = name.replace(/^oasis_/, "");
        return base.charAt(0).toUpperCase() + base.slice(1);
    }

    function swatches(name) {
        const c = root.colors[name] || {};
        return root.swatch_keys.map(k => c[k] || "transparent");
    }

    // Saves the palette, reloads Hyprland and reruns every generator through switch.lua.
    function apply(name) {
        if (!(name in root.colors)) return false;
        root.current = name;
        Quickshell.execDetached([root.switch_script, "--set", name]);
        return true;
    }

    // Writes the flag before rerunning the switcher, so the generators see the new value.
    function set_nvim_sync(on) {
        root.nvim_sync = on;
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" > "$2" && { [ -z "$4" ] || exec "$3" --set "$4"; }', "sh", on ? "on" : "off", root.state_dir + "/nvim_sync", root.switch_script, root.current]);
    }

    Process {
        id: loader
        command: [Quickshell.shellDir + "/scripts/palettes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.colors = JSON.parse(text);
                } catch (e) {
                    console.warn("Palettes: bad palette list (" + e + ")");
                }
            }
        }
    }

    FileView {
        id: current_file
        path: root.state_dir + "/theme"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.current = text().trim();
            root.settled = true;
        }
        onLoadFailed: error => root.settled = true
    }

    FileView {
        path: root.state_dir + "/nvim_sync"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.nvim_sync = text().trim() === "on"
    }

    Component.onCompleted: loader.running = true
}
