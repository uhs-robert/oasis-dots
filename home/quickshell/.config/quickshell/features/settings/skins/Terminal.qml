import QtQuick
import QtQuick.Layouts
import qs.ui.menu
import qs.theme

// Terminal: a shell prompt on the selected row and a faint rule down the panel's left edge, like a tmux pane border.
// Layout, keys and focus stay with SettingsPopup; see Default.qml for the slot contract.
QtObject {
    readonly property Component nav_item: Component {
        MenuRow {
            id: row
            property var ctx: ({ st: Style, section: { glyph: "", label: "" }, index: 0, selected: false, text_bump: 0 })
            // Room for the prompt, so the label does not shift when the row is selected.
            readonly property real prompt_space: Style.px(18)
            readonly property real need: 16 + row.inset + row.prompt_space + row.key_space + layout.implicitWidth

            base_radius: 2
            selected: row.ctx.selected
            key: row.ctx.index < 9 ? String(row.ctx.index + 1) : ""

            Text {
                visible: row.selected
                x: Style.px(6)
                anchors.verticalCenter: parent.verticalCenter
                text: ">"
                color: row.ctx.st.caret_color
                font.family: row.ctx.st.mono_font
                font.pixelSize: row.ctx.st.font_size + row.ctx.text_bump
                font.bold: true
            }

            RowLayout {
                id: layout
                anchors.left: parent.left
                anchors.leftMargin: 8 + row.inset + row.prompt_space
                anchors.right: parent.right
                anchors.rightMargin: 8 + row.key_space
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    text: row.ctx.section.glyph
                    color: row.fg(row.ctx.st.text_accent)
                    font.family: row.ctx.st.font_family
                    font.pixelSize: row.ctx.st.font_size + row.ctx.text_bump
                }

                RowLabel {
                    Layout.fillWidth: true
                    label: row.ctx.section.label
                    color: row.fg(row.selected ? row.ctx.st.text_fg : row.ctx.st.text_muted)
                    font.family: row.ctx.st.font_family
                    font.pixelSize: row.ctx.st.font_size + row.ctx.text_bump
                }
            }
        }
    }

    readonly property Component backdrop: Component {
        Item {
            property var ctx
        }
    }

    // Brighter rule while a pane has the cursor, as tmux marks the active pane.
    readonly property Component panel_art: Component {
        Item {
            id: art
            property var ctx
            Rectangle {
                // Follows the help divider, which sits Style.px(12) outside the help area, so it never touches the text.
                readonly property bool below: art.ctx.help_below
                x: below ? 0 : -Style.px(12)
                y: below ? -Style.px(12) : 0
                width: below ? parent.width : 1
                height: below ? 1 : parent.height
                color: art.ctx.in_pane ? art.ctx.st.caret_color : art.ctx.st.text_muted
                opacity: art.ctx.in_pane ? 0.9 : 0.35
            }
        }
    }
}
