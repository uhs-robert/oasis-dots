// home/quickshell/.config/quickshell/components/region/Toolbar.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

// Action toolbar under, over or inside the confirmed selection.
Rectangle {
    id: root

    required property rect sel
    required property bool shown
    required property bool readout_above
    required property real readout_height
    required property string delay_label

    signal run(int index)

    visible: root.shown
    readonly property real gap: 10
    readonly property bool below: root.sel.y + root.sel.height + gap + height <= parent.height
    readonly property bool over: !root.below && root.sel.y >= height + gap + root.readout_height + 12
    x: Math.max(8, Math.min(parent.width - width - 8, root.sel.x + (root.sel.width - width) / 2))
    y: root.below ? root.sel.y + root.sel.height + gap : root.over ? root.sel.y - height - gap - (root.readout_above ? root.readout_height + 6 : 0) : root.sel.y + root.sel.height - height - gap
    width: tools_row.implicitWidth + 16
    height: tools_row.implicitHeight + 16 + Style.accent_height
    radius: Style.frame_radius
    color: Style.frame_color
    border.width: Style.frame_border_width
    border.color: Style.frame_border_color

    MouseArea {
        anchors.fill: parent
    }

    Rectangle {
        width: parent.width
        height: Style.accent_height
        color: Style.accent_color
        topLeftRadius: root.radius
        topRightRadius: root.radius
    }

    RowLayout {
        id: tools_row
        x: 8
        y: 8 + Style.accent_height
        spacing: 4

        Repeater {
            model: Screenshot.actions

            MenuRow {
                id: tool
                required property int index
                required property var modelData

                Layout.preferredWidth: tool_label.implicitWidth + 16 + tool.inset + tool.key_space
                Layout.preferredHeight: Style.px(28)
                base_radius: 6
                selected: tool.index === Screenshot.tool_index
                key: tool.modelData.key

                Text {
                    id: tool_label
                    anchors.left: parent.left
                    anchors.leftMargin: 8 + tool.inset
                    anchors.verticalCenter: parent.verticalCenter
                    text: tool.modelData.label
                    color: tool.fg(Style.text_fg)
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: Screenshot.tool_index = tool.index
                    onClicked: root.run(tool.index)
                }
            }
        }

        MenuRow {
            id: delay_tool
            visible: !Screenshot.frozen
            Layout.preferredWidth: delay_text.implicitWidth + 16 + delay_tool.inset + delay_tool.key_space
            Layout.preferredHeight: Style.px(28)
            base_radius: 6
            key: "d"

            Text {
                id: delay_text
                anchors.left: parent.left
                anchors.leftMargin: 8 + delay_tool.inset
                anchors.verticalCenter: parent.verticalCenter
                text: root.delay_label
                color: Screenshot.delay_s > 0 ? Theme.warning : Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.font_size
            }

            MouseArea {
                anchors.fill: parent
                onClicked: Screenshot.cycle_delay()
            }
        }
    }
}
