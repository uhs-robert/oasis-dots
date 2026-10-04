// home/quickshell/.config/quickshell/components/region/SelectionChrome.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../services"
import ".."

// Dimming around the selection, fallback target outlines, the selection frame and its size readout.
Item {
    id: root

    required property rect sel
    required property bool mine
    required property bool pixel_mode
    required property bool target_mode
    required property bool skinned_targets
    required property color dim_color
    required property string screen_name

    readonly property bool readout_above: readout.above
    readonly property real readout_height: readout.height

    anchors.fill: parent

    Rectangle {
        visible: !root.mine && !root.pixel_mode
        anchors.fill: parent
        color: root.dim_color
    }

    Rectangle {
        visible: root.mine
        width: parent.width
        height: root.sel.y
        color: root.dim_color
    }

    Rectangle {
        visible: root.mine
        y: root.sel.y + root.sel.height
        width: parent.width
        height: parent.height - y
        color: root.dim_color
    }

    Rectangle {
        visible: root.mine
        y: root.sel.y
        width: root.sel.x
        height: root.sel.height
        color: root.dim_color
    }

    Rectangle {
        visible: root.mine
        x: root.sel.x + root.sel.width
        y: root.sel.y
        width: parent.width - x
        height: root.sel.height
        color: root.dim_color
    }

    Repeater {
        model: root.target_mode ? Screenshot.targets : []

        Rectangle {
            required property var modelData
            required property int index
            visible: !root.skinned_targets && modelData.screen === root.screen_name && index !== Screenshot.target_index && Screenshot.phase === "select"
            x: modelData.rect.x
            y: modelData.rect.y
            width: modelData.rect.width
            height: modelData.rect.height
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Style.accent_color, 0.5)
        }
    }

    Item {
        id: frame
        readonly property int edge: Math.max(1, Style.frame_border_width)
        visible: root.mine && !root.skinned_targets
        x: root.sel.x - frame.edge
        y: root.sel.y - frame.edge
        width: root.sel.width + frame.edge * 2
        height: root.sel.height + frame.edge * 2

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: frame.edge
            border.color: Style.accent_color
        }

        CornerBrackets {
            anchors.fill: parent
            color: Style.caret_color
            inset: -2
            arm: Math.min(18, Math.max(6, Math.min(root.sel.width, root.sel.height) / 3))
            thickness: 3
            all_corners: true
        }
    }

    Rectangle {
        id: readout
        visible: root.mine && !root.skinned_targets
        readonly property bool above: root.sel.y >= height + 8
        x: Math.max(0, Math.min(parent.width - width, root.sel.x))
        y: readout.above ? root.sel.y - height - 6 : root.sel.y + 6
        width: readout_text.implicitWidth + 16
        height: readout_text.implicitHeight + 6
        radius: Style.radius(3)
        color: Style.title_bg
        border.width: Style.frame_border_width > 0 ? 1 : 0
        border.color: Style.frame_border_color

        Text {
            id: readout_text
            anchors.centerIn: parent
            text: Math.round(root.sel.width) + " x " + Math.round(root.sel.height)
            color: Style.title_fg
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-3)
        }
    }
}
