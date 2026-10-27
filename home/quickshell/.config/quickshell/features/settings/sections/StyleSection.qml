import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.theme.transitions
import qs.services
import qs.features.settings
import qs.features.osd

RowsSection {
    id: root

    readonly property var osd_edge_names: ({ opposite: "Opposite the bar", left: "Left edge", right: "Right edge" })
    // The palette card shows only on the Colors rows, and follows the open Palette list.
    readonly property bool on_colors: root.cursor_heading === "Colors"
    readonly property string card_name: root.on_colors && root.highlighted_value !== undefined ? root.highlighted_value : Palettes.current

    footer_hint: "j/k move · " + root.layout_hint + "Enter list · h/Esc sections · q close"
    rows: [
        { heading: "Style" },
        {
            label: "Style",
            desc: "The shell's look: fonts, frames, meters and sounds. Colors come from the palette.",
            values: () => Style.names,
            text: v => Style.label(v) + (v === Style.saved_name ? " (active)" : ""),
            value: () => Style.saved_name,
            set: v => Transitions.commit(v),
            cycle: false
        },
        { heading: "Colors" },
        {
            label: "Palette",
            desc: "The Oasis palette for the shell, Hyprland and terminal apps. Applies at once.",
            values: () => Palettes.ready ? Palettes.names : [],
            text: v => Palettes.label(v) + (v === Palettes.current ? " (active)" : ""),
            value: () => Palettes.current,
            set: v => Palettes.apply(v),
            cycle: false
        },
        {
            label: "Sync Neovim",
            desc: "Switch Neovim's colorscheme along with the palette. Off leaves Neovim alone.",
            values: () => ["on", "off"],
            text: v => v,
            value: () => Palettes.nvim_sync ? "on" : "off",
            set: v => Palettes.set_nvim_sync(v === "on")
        },
        { heading: "Screen" },
        {
            label: "Flush single windows",
            desc: "A lone window sits flush against the screen frame. Off, it keeps the gaps and rounding of any other window. Applies to every style that has its Screen frame on (Theme options).",
            // Fixed while the style's frame is off: the setting does nothing then, and keeps its value for when it is on.
            values: () => Style.screen_frame_on ? ["on", "off"] : [Style.flush_single ? "on (needs the screen frame)" : "off (needs the screen frame)"],
            text: v => v,
            value: () => Style.screen_frame_on ? (Style.flush_single ? "on" : "off") : (Style.flush_single ? "on (needs the screen frame)" : "off (needs the screen frame)"),
            set: v => {
                if (Style.screen_frame_on) Style.set_flush_single(v === "on");
            },
            cycle: Style.screen_frame_on,
            pick: false
        },
        {
            label: "Hot corners",
            desc: "Moving the pointer into the top-left screen corner opens the workspace overview.",
            values: () => ["on", "off"],
            text: v => v,
            value: () => HotCornersSettings.enabled ? "on" : "off",
            set: v => HotCornersSettings.set_enabled(v === "on")
        },
        {
            label: "OSD edge",
            desc: "The screen edge the volume, brightness and voice OSD comes out of, on every monitor. On a side edge it sits centred, with the same panel as on top or bottom.",
            values: () => OsdSettings.choices.edge,
            text: v => root.osd_edge_names[v] || String(v),
            value: () => OsdSettings.edge,
            set: v => OsdSettings.set("edge", v)
        }
    ]

    preview: Rectangle {
        id: card
        objectName: "card"
        visible: root.on_colors
        readonly property var c: Palettes.colors[root.card_name] || ({})
        Layout.fillWidth: true
        Layout.preferredHeight: card_col.implicitHeight + 16
        color: card.c.bg_core || "transparent"
        border.width: 1
        border.color: card.c.ui_border || "transparent"
        radius: Style.px(4)

        ColumnLayout {
            id: card_col
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            Text {
                text: Palettes.label(root.card_name)
                color: card.c.theme_primary || "transparent"
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size
            }

            Text {
                Layout.fillWidth: true
                text: "Body text and a <b>strong</b> word"
                textFormat: Text.RichText
                color: card.c.fg_core || "transparent"
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            // Flows, since the help column beside the rows is narrow.
            Flow {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: ["theme_primary", "theme_secondary", "theme_accent", "ok", "warning", "error", "info", "hint"]

                    Text {
                        required property string modelData
                        text: modelData.replace("theme_", "")
                        color: card.c[modelData] || "transparent"
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: Palettes.swatch_keys.concat(["yellow", "cyan", "bright_black", "bright_white"])

                    Rectangle {
                        required property string modelData
                        width: Style.px(14)
                        height: Style.px(10)
                        radius: 2
                        color: card.c[modelData] || "transparent"
                    }
                }
            }
        }
    }
}
