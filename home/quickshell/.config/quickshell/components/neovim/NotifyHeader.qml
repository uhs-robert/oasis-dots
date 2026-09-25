// home/quickshell/.config/quickshell/components/neovim/NotifyHeader.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"

// An nvim-notify title line: level icon and app in the level color, a level tag, the age at the right, a rule under it.
Item {
    id: root

    property string app: ""
    property string age: ""
    // "critical", "low" or "" for normal.
    property string level: ""
    property color accent: Theme.info

    implicitHeight: row.implicitHeight + 7

    RowLayout {
        id: row
        width: parent.width
        spacing: 7

        Text {
            text: root.level === "critical" ? "\u{f057}" : root.level === "low" ? "\u{f0a2}" : "\u{f05a}"
            color: root.accent
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
        }

        Text {
            Layout.fillWidth: !level_tag.visible
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: root.app
            color: root.accent
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
            font.bold: true
        }

        Rectangle {
            id: level_tag
            visible: root.level !== ""
            implicitWidth: level_text.implicitWidth + 10
            implicitHeight: level_text.implicitHeight
            radius: 3
            color: Qt.alpha(root.accent, 0.16)

            Text {
                id: level_text
                anchors.centerIn: parent
                text: root.level
                color: root.accent
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }
        }

        Item {
            visible: level_tag.visible
            Layout.fillWidth: true
        }

        Text {
            text: root.age
            color: Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.bg_surface
    }
}
