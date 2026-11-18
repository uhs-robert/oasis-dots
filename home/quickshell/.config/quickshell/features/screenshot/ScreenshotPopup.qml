pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.ui.menu
import qs.theme
import qs.features.popups
import qs.features.popups.frames

Popup {
    id: root

    popup_name: "screenshot"
    title: "Screenshot"
    preferred_width: 250
    // Hands-off (Screenshot.open_menu): no keyboard focus, no mouse. The Screenshot submap presses the keys.
    footer_hint: "Esc close"
    key_help: ""
    body_height: content.implicitHeight + 24

    readonly property var rows: Screenshot.menu_rows

    function glyph_color(row) {
        return row.section === "Record" ? Style.pal.warning : row.section === "Tools" ? Style.pal.secondary : Style.pal.primary;
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: rows_col.implicitHeight

        ColumnLayout {
            id: rows_col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4

            Repeater {
                model: root.rows

                ColumnLayout {
                    id: row_wrap
                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 2

                    MenuSection {
                        visible: row_wrap.index === 0 || root.rows[row_wrap.index - 1].section !== row_wrap.modelData.section
                        topPadding: row_wrap.index === 0 ? 0 : 6
                        label: row_wrap.modelData.section
                    }

                    MenuRow {
                        id: row
                        Layout.fillWidth: true
                        Layout.preferredHeight: Style.px(28)
                        base_radius: 6
                        key: row_wrap.modelData.key

                        RowLayout {
                            anchors.left: parent.left
                            anchors.leftMargin: 8 + row.inset
                            anchors.right: parent.right
                            anchors.rightMargin: 8 + row.key_space
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Text {
                                text: row_wrap.modelData.glyph
                                color: row.fg(root.glyph_color(row_wrap.modelData))
                                font.family: root.st.font_family
                                font.pixelSize: root.st.font_size
                            }

                            RowLabel {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                label: row_wrap.modelData.label
                                color: row.fg(root.st.text_fg)
                                font.family: root.st.font_family
                                font.pixelSize: root.st.font_size
                            }
                        }
                    }
                }
            }
        }
    }
}
