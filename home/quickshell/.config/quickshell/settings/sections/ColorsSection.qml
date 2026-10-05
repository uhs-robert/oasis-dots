// home/quickshell/.config/quickshell/settings/sections/ColorsSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    readonly property string card_name: root.highlighted_value ?? Palettes.current

    footer_hint: "j/k move · Enter list · Esc sections · q close"
    rows: [
        {
            label: "Palette",
            values: () => Palettes.ready ? Palettes.names : [],
            text: v => Palettes.label(v) + (v === Palettes.current ? " (active)" : ""),
            value: () => Palettes.current,
            set: v => Palettes.apply(v),
            cycle: false
        },
        {
            label: "Sync Neovim",
            values: () => ["on", "off"],
            text: v => v,
            value: () => Palettes.nvim_sync ? "on" : "off",
            set: v => Palettes.set_nvim_sync(v === "on")
        }
    ]

    footer: Rectangle {
        id: card
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

            Row {
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

            Row {
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
