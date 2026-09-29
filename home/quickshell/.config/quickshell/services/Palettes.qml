// home/quickshell/.config/quickshell/services/Palettes.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// The Oasis palettes Hyprland's theme switcher knows, the active one, and applying a choice through that switcher.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string switch_script: root.home + "/.config/hypr/theme/switch.lua"
    // Palette name to { key: "#hex" }.
    property var colors: ({})
    readonly property var names: Object.keys(root.colors)
    property string current: ""
    readonly property var swatch_keys: ["bg_core", "bg_surface", "fg_core", "theme_primary", "theme_secondary", "theme_accent", "green", "red", "blue", "magenta"]

    function label(name) {
        const base = name.replace(/^oasis_/, "");
        return base.charAt(0).toUpperCase() + base.slice(1);
    }

    function swatches(name) {
        const c = root.colors[name] || {};
        return root.swatch_keys.map(k => c[k] || "transparent");
    }

    // Shows a palette on the whole shell without saving it.
    function preview(name) {
        if (name in root.colors) Theme.apply(root.colors[name]);
    }

    function restore() {
        Theme.restore();
    }

    // Saves the palette, reloads Hyprland and reruns every generator through switch.lua.
    function apply(name) {
        if (!(name in root.colors)) return false;
        root.current = name;
        Quickshell.execDetached([root.switch_script, "--set", name]);
        return true;
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
        path: root.home + "/.config/hypr/theme/.current_theme"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.current = text().trim()
        onLoadFailed: error => {}
    }

    Component.onCompleted: loader.running = true
}
