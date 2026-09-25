// home/quickshell/.config/quickshell/components/ps2/DialogPrompt.qml
import QtQuick
import "../../theme"
import ".."

// A PS2 system dialog's prompt line: each entry is { button or key, text } and clicks run its action.
Row {
    id: root

    // [{ button: "cross" | key: "d", text: "Open", action: function }]
    property var entries: []

    spacing: 14

    Repeater {
        model: root.entries

        MouseArea {
            id: entry
            required property var modelData
            implicitWidth: entry_row.implicitWidth
            implicitHeight: entry_row.implicitHeight
            onClicked: if (entry.modelData.action) entry.modelData.action()

            Row {
                id: entry_row
                spacing: 5

                Ps2Button {
                    visible: !!entry.modelData.button
                    anchors.verticalCenter: parent.verticalCenter
                    button: entry.modelData.button || "cross"
                    size: Style.fs(-1)
                }

                KeyBadge {
                    visible: !entry.modelData.button
                    anchors.verticalCenter: parent.verticalCenter
                    key: entry.modelData.key || ""
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.modelData.text
                    color: Theme.fg_core
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                    font.weight: Font.Light
                }
            }
        }
    }
}
