import QtQuick
import QtQuick.Layouts
import qs.ui.menu
import qs.theme

// The look every style gets unless it has its own skin file. A skin holds three parts as Components, and SettingsPopup
// loads each with a `ctx` property (st, text_bump, row_extra, group_fg, portrait, in_pane, nav_index, body_width,
// body_height, help_below (the help text sits under the pane, not beside it); nav_item adds section, index and selected). A skin never takes focus or keys: SettingsPopup owns them.
// A skin may also give an optional `layout` part that replaces the whole body; Default does not, see the README.
QtObject {
    // One section row. Sets `need`, the width the row wants, which SettingsPopup takes the widest of for the list.
    // The row's height is the popup's pitch, not the skin's.
    readonly property Component nav_item: Component {
        MenuRow {
            id: row
            // Filled by SettingsPopup right after creation; the blank keeps the bindings quiet until then.
            property var ctx: ({ st: Style, section: { glyph: "", label: "" }, index: 0, selected: false, text_bump: 0 })
            readonly property real need: 16 + row.inset + row.key_space + layout.implicitWidth

            base_radius: 6
            selected: row.ctx.selected
            key: row.ctx.index < 9 ? String(row.ctx.index + 1) : ""

            RowLayout {
                id: layout
                anchors.left: parent.left
                anchors.leftMargin: 8 + row.inset
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
                    color: row.fg(row.ctx.st.text_fg)
                    font.family: row.ctx.st.font_family
                    font.pixelSize: row.ctx.st.font_size + row.ctx.text_bump
                }
            }
        }
    }

    // Behind the whole body, filling it.
    readonly property Component backdrop: Component {
        Item {
            property var ctx
        }
    }

    // Over the docked panel, filling it.
    readonly property Component panel_art: Component {
        Item {
            property var ctx
        }
    }
}
