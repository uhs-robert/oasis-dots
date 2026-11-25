import QtQuick
import QtQuick.Layouts
import qs.ui.menu
import qs.theme
import qs.styles.goldeneye.widgets

// The pause-watch look for Settings: mono section rows with a lit marker on the selected one, no backdrop, and a live
// watch dial in the docked panel. The contract is in features/settings/README.md ("A settings skin").
QtObject {
    readonly property Component nav_item: Component {
        MenuRow {
            id: row
            // Filled by SettingsPopup right after creation; the blank keeps the bindings quiet until then.
            property var ctx: ({ st: Style, section: { glyph: "", label: "" }, index: 0, selected: false, text_bump: 0 })
            readonly property real need: 16 + row.inset + row.key_space + 10 + layout.implicitWidth
            readonly property color lit: row.ctx.st.wk.lit

            base_radius: 2
            selected: row.ctx.selected
            key: row.ctx.index < 9 ? String(row.ctx.index + 1) : ""

            Rectangle {
                visible: row.selected
                x: 2
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: parent.height * 0.6
                color: row.lit
            }

            RowLayout {
                id: layout
                anchors.left: parent.left
                anchors.leftMargin: 14 + row.inset
                anchors.right: parent.right
                anchors.rightMargin: 8 + row.key_space
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    text: row.ctx.section.glyph
                    color: row.selected ? row.lit : row.ctx.st.text_accent
                    font.family: row.ctx.st.font_family
                    font.pixelSize: row.ctx.st.font_size + row.ctx.text_bump
                }

                RowLabel {
                    Layout.fillWidth: true
                    label: row.ctx.section.label
                    color: row.selected ? row.lit : row.ctx.st.text_fg
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

    // Bottom corner of the panel. Hidden when help is stacked under the pane (a thin strip) or when the help column is
    // full (a split picker list or long help), so the dial never covers content.
    readonly property Component panel_art: Component {
        Item {
            id: art
            property var ctx: ({ help_below: true, help_full: true, body_height: 0 })

            SettingsWatch {
                readonly property real side: Math.round(Math.min(art.width * 0.5, art.height * 0.3, 150))
                visible: !art.ctx.help_below && !art.ctx.help_full && side >= 64
                running: art.visible && art.Window.window !== null && art.Window.window.visible
                width: side
                height: side
                anchors.right: parent.right
                anchors.bottom: parent.bottom
            }
        }
    }
}
