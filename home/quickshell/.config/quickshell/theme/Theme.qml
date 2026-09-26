// home/quickshell/.config/quickshell/theme/Theme.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property color bg_shadow: "#05070A"
    property color bg_core: "#0C0E13"
    property color bg_crust: "#070A0E"
    property color bg_mantle: "#141C24"
    property color bg_surface: "#1E2A38"

    property color fg_core: "#F5F5DC"
    property color fg_strong: "#FFFFF0"
    property color fg_muted: "#4E6578"
    property color fg_dim: "#717A84"
    property color fg_inlay: "#7D7965"

    property color theme_primary: "#7FA3C9"
    property color theme_secondary: "#F0E68C"
    property color theme_accent: "#FFA0A0"

    property color error: "#FFA0A0"
    property color warning: "#F0E68C"
    property color info: "#81C0FF"
    property color hint: "#8AD3BE"
    property color ok: "#A3E39A"

    property color theme_primary_strong: "#5D8BBB"
    property color theme_primary_light: "#B0C8DE"
    property color theme_secondary_strong: "#BDB76B"
    property color theme_label: "#FF7979"
    property color theme_cursor: "#F0E68C"

    property color ui_border: "#5D8BBB"
    property color ui_title: "#7FA3C9"
    property color ui_dir: "#87CEEB"
    property color ui_cursor_line: "#1E2A38"
    property color ui_nontext: "#717A84"
    property color ui_visual_bg: "#24364D"
    property color ui_search_bg: "#666666"
    property color ui_search_fg: "#F5F5DC"
    property color ui_match_bg: "#CDC673"
    property color ui_match_fg: "#0C0E13"
    property color ui_float_bg: "#070A0E"
    property color ui_float_fg: "#FFFFF0"
    property color ui_float_title: "#F0E68C"
    property color ui_float_border: "#5D8BBB"
    property color ui_picker_bg: "#070A0E"
    property color ui_picker_fg: "#FFFFF0"
    property color ui_picker_title: "#F0E68C"
    property color ui_picker_border: "#BDB76B"

    property color error_bg: "#532E2E"
    property color warning_bg: "#4D4528"
    property color info_bg: "#335668"
    property color hint_bg: "#2B4A46"

    property color black: "#0C0E13"
    property color red: "#FF7979"
    property color green: "#7FCF78"
    property color yellow: "#F0E68C"
    property color blue: "#81C0FF"
    property color magenta: "#C695FF"
    property color cyan: "#69C3AA"
    property color white: "#F5F5DC"
    property color bright_black: "#4E6578"
    property color bright_red: "#FFA0A0"
    property color bright_green: "#A3E39A"
    property color bright_yellow: "#F8B471"
    property color bright_blue: "#87CEEB"
    property color bright_magenta: "#D2ADFF"
    property color bright_cyan: "#8AD3BE"
    property color bright_white: "#FFFFF0"

    property color syntax_bracket: "#A3ABB8"
    property color syntax_builtin_const: "#8D8DE7"
    property color syntax_builtin_func: "#E0AA87"
    property color syntax_builtin_var: "#C28EFF"
    property color syntax_comment: "#69809D"
    property color syntax_conditional: "#BDB76B"
    property color syntax_constant: "#FF9633"
    property color syntax_delimiter: "#1670AD"
    property color syntax_exception: "#FF7979"
    property color syntax_func: "#E9C0A5"
    property color syntax_identifier: "#87CEEB"
    property color syntax_macro: "#9CBC4E"
    property color syntax_operator: "#CDC673"
    property color syntax_parameter: "#7FCF78"
    property color syntax_preproc: "#ADC76B"
    property color syntax_punctuation: "#9B9746"
    property color syntax_regex: "#FFC0C0"
    property color syntax_special: "#FFBA75"
    property color syntax_statement: "#D8CF7F"
    property color syntax_string: "#FFA0A0"
    property color syntax_type: "#7CCDB5"
    property color syntax_typedef: "#55B69D"

    property string font_family: "Maple Mono NF"
    property int font_size: 13
    property int glyph_size: 19
    property int popup_font_size: 15

    // QS_THEME_JSON (set by the greeter) is read first; if it is missing or invalid the bundled theme.json is used.
    property string override_path: Quickshell.env("QS_THEME_JSON") || ""

    FileView {
        id: theme_file
        path: root.override_path !== "" ? root.override_path : Quickshell.shellDir + "/theme/theme.json"
        watchChanges: true
        printErrors: root.override_path === ""
        onFileChanged: reload()
        onLoadFailed: error => {
            if (root.override_path !== "") root.override_path = "";
        }
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("not an object");
                root.apply(data);
            } catch (e) {
                console.warn("theme.json: " + e);
                if (root.override_path !== "") root.override_path = "";
            }
        }
    }

    function apply(data) {
        for (const key in data) {
            if (key in root && typeof data[key] === "string" && data[key] !== "") {
                root[key] = data[key];
            }
        }
    }
}
