import QtQuick
import qs.theme
import qs.ui.keys
import "../../ui/keys/KeyHints.js" as KeyHints

// Design C: a mode block on the left (label over the layout state), then one column per key group, each with a small heading
// over its keys: two rows without splitting a group.
Row {
    id: root
    required property var groups
    required property string mode_label
    required property string state_label
    spacing: 18

    Rectangle {
        visible: root.mode_label !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(mode_text.implicitWidth, state_text.implicitWidth) + 24
        height: block.implicitHeight + 14
        radius: Math.min(Style.frame_radius, 4)
        color: Style.title_bg
        Column {
            id: block
            anchors.centerIn: parent
            spacing: 2
            Text {
                id: mode_text
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.mode_label
                color: Style.title_fg
                font.family: Style.title_font_family
                font.pixelSize: Style.fs(0)
                font.bold: true
            }
            Text {
                id: state_text
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.state_label !== ""
                text: root.state_label
                color: Style.title_fg
                opacity: 0.7
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }
    }
    Repeater {
        model: root.groups
        Column {
            id: col
            required property var modelData
            spacing: 4
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: col.modelData.name.toUpperCase()
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
                font.letterSpacing: 1.5
            }
            Rectangle {
                width: parent.width
                height: 1
                color: Style.accent_color
                opacity: 0.6
            }
            Row {
                spacing: 12
                Repeater {
                    model: col.modelData.keys
                    Row {
                        id: item
                        required property var modelData
                        spacing: 4
                        Text {
                            text: KeyHints.with_glyphs(item.modelData[0])
                            color: Style.accent_color
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-1)
                            font.bold: true
                        }
                        Text {
                            text: item.modelData[1]
                            color: Style.text_fg
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-1)
                        }
                    }
                }
            }
        }
    }
}
