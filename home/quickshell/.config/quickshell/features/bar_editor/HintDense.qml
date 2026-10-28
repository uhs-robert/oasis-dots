import QtQuick
import qs.theme
import "../../ui/keys/KeyHints.js" as KeyHints

// Design B: one dense row, bare accent keys with muted labels, thin rules between groups, mode as a tab-style label on the left.
Row {
    id: root
    required property var groups
    required property string mode_label
    spacing: 14

    Text {
        visible: root.mode_label !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.mode_label
        color: Style.accent_color
        font.family: Style.title_font_family
        font.pixelSize: Style.fs(-1)
        font.bold: true
    }
    Repeater {
        model: root.groups
        Row {
            id: grp
            required property var modelData
            spacing: 14
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 14
                color: Style.frame_border_color
            }
            Repeater {
                model: grp.modelData.keys
                Row {
                    id: item
                    required property var modelData
                    spacing: 5
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: KeyHints.with_glyphs(item.modelData[0])
                        color: Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-1)
                        font.bold: true
                    }
                    Text {
                        text: item.modelData[1]
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-1)
                    }
                }
            }
        }
    }
}
