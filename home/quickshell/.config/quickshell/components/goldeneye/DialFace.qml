// home/quickshell/.config/quickshell/components/goldeneye/DialFace.qml
import QtQuick
import "../../lock/skins/goldeneye" as Watch
import "../../lock/skins/goldeneye/Watch.js" as W

// A round watch dial of any size: black face, warm arc left and blue arc right, white bars and studs, and a green octagon panel that holds the children.
Item {
    id: root

    property int warm_lit: 8
    property int cold_lit: 8
    property bool from_bottom: false
    property var cold_colors: W.cold_lit
    property real arc_opacity: 1
    default property alias content: panel.data
    readonly property alias panel_item: panel

    width: 124
    height: width

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: W.black
        border.width: 2
        border.color: W.rim
    }

    Watch.SegmentArc {
        x: root.width * 0.048
        y: (root.height - height) / 2
        width: root.width * 0.194
        height: root.height * 0.726
        thickness: root.width * 0.065
        gap: 3
        colors: W.warm
        lit: root.warm_lit
        from_bottom: root.from_bottom
        opacity: root.arc_opacity
    }

    Watch.SegmentArc {
        x: root.width - root.width * 0.048 - width
        y: (root.height - height) / 2
        width: root.width * 0.194
        height: root.height * 0.726
        thickness: root.width * 0.065
        gap: 3
        mirror: true
        colors: root.cold_colors
        lit: root.cold_lit
        from_bottom: root.from_bottom
        opacity: root.arc_opacity
    }

    Repeater {
        model: [-4, 4]

        Rectangle {
            required property int modelData
            x: root.width / 2 + modelData * root.width / 124 - 2 * root.width / 124
            y: root.width * 0.04
            width: root.width * 0.032
            height: root.width * 0.073
            color: W.white
        }
    }

    Rectangle {
        x: root.width / 2 - root.width * 0.016
        y: root.height - root.width * 0.113
        width: root.width * 0.032
        height: root.width * 0.073
        color: W.white
    }

    Repeater {
        model: [[-1, -1], [1, -1], [-1, 1], [1, 1]]

        Rectangle {
            required property var modelData
            x: root.width / 2 + modelData[0] * root.width * 0.218 - root.width * 0.024
            y: root.height / 2 + modelData[1] * root.width * 0.323 - root.width * 0.024
            width: root.width * 0.048
            height: width
            radius: width / 2
            color: W.white
        }
    }

    Watch.PanelShape {
        id: panel
        anchors.centerIn: parent
        width: root.width * 0.5
        height: width
        cut: root.width * 0.073
        notches: false
        clip: true
    }
}
