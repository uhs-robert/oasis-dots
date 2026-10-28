import QtQuick
import qs.theme
import qs.ui.keys
import "HintData.js" as HintData
import "../../ui/keys/KeyHints.js" as KeyHints

// Design A: keycap chips, groups side by side, split over two rows with the mode label heading the first.
Column {
    id: root
    required property var groups
    required property string mode_label
    spacing: 6
    readonly property int split: Math.ceil(root.groups.length / 2)

    component Line: Row {
        id: line
        required property var items
        spacing: 22
        anchors.horizontalCenter: parent.horizontalCenter
        Repeater {
            model: line.items
            Row {
                id: grp
                required property var modelData
                spacing: 12
                Repeater {
                    model: grp.modelData.keys
                    Row {
                        id: item
                        required property var modelData
                        spacing: 5
                        anchors.verticalCenter: parent.verticalCenter
                        KeyBadge {
                            anchors.verticalCenter: parent.verticalCenter
                            key: KeyHints.with_glyphs(item.modelData[0])
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
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

    Rectangle {
        visible: root.mode_label !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        width: mode_text.implicitWidth + 24
        height: mode_text.implicitHeight + 4
        radius: Math.min(Style.frame_radius, 4)
        color: Style.title_bg
        Text {
            id: mode_text
            anchors.centerIn: parent
            text: root.mode_label
            color: Style.title_fg
            font.family: Style.title_font_family
            font.pixelSize: Style.fs(-2)
            font.bold: true
            font.letterSpacing: 2
        }
    }
    Line { items: root.groups.slice(0, root.split) }
    Line { visible: root.groups.length > root.split; items: root.groups.slice(root.split) }
}
