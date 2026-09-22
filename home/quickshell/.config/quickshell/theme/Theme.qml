// home/quickshell/.config/quickshell/theme/Theme.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property color bg_core: "#0C0E13"
    property color bg_mantle: "#141C24"
    property color bg_shadow: "#05070A"
    property color bg_surface: "#1E2A38"

    property color fg_core: "#F5F5DC"
    property color fg_strong: "#FFFFF0"
    property color fg_muted: "#4E6578"
    property color fg_dim: "#717A84"

    property color primary: "#7FA3C9"
    property color secondary: "#F0E68C"
    property color accent: "#FFA0A0"
    property color yellow: "#F0E68C"

    property color error: "#FFA0A0"
    property color warning: "#F0E68C"
    property color info: "#81C0FF"
    property color hint: "#8AD3BE"
    property color ok: "#A3E39A"

    property color red: "#FF7979"
    property color green: "#7FCF78"
    property color blue: "#81C0FF"
    property color cyan: "#69C3AA"
    property color magenta: "#C695FF"

    property string font_family: "Maple Mono NF"
    property int font_size: 15

    FileView {
        id: theme_file
        path: Quickshell.shellDir + "/theme/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.apply(JSON.parse(text()));
            } catch (e) {
                console.warn("theme.json: " + e);
            }
        }
    }

    function apply(data) {
        if (data.bg_core) root.bg_core = data.bg_core;
        if (data.bg_mantle) root.bg_mantle = data.bg_mantle;
        if (data.bg_shadow) root.bg_shadow = data.bg_shadow;
        if (data.bg_surface) root.bg_surface = data.bg_surface;
        if (data.fg_core) root.fg_core = data.fg_core;
        if (data.fg_strong) root.fg_strong = data.fg_strong;
        if (data.fg_muted) root.fg_muted = data.fg_muted;
        if (data.fg_dim) root.fg_dim = data.fg_dim;
        if (data.primary) root.primary = data.primary;
        if (data.secondary) root.secondary = data.secondary;
        if (data.accent) root.accent = data.accent;
        if (data.yellow) root.yellow = data.yellow;
        if (data.error) root.error = data.error;
        if (data.warning) root.warning = data.warning;
        if (data.info) root.info = data.info;
        if (data.hint) root.hint = data.hint;
        if (data.ok) root.ok = data.ok;
        if (data.red) root.red = data.red;
        if (data.green) root.green = data.green;
        if (data.blue) root.blue = data.blue;
        if (data.cyan) root.cyan = data.cyan;
        if (data.magenta) root.magenta = data.magenta;
    }
}
