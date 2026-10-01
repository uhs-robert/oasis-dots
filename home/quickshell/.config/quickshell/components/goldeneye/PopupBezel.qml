// home/quickshell/.config/quickshell/components/goldeneye/PopupBezel.qml
import QtQuick
import "../../lock/skins/goldeneye" as Watch
import "../../lock/skins/goldeneye/Watch.js" as W

// The popup frame as the classic watch: warm and blue segment columns, white bars and studs on the bezel, the green octagon panel inside.
Item {
    id: root

    required property var st
    property real edge: root.st.inset_pad + root.st.lcd_margin
    property real rim: root.st.frame_border_width
    readonly property real band: root.edge - root.rim
    readonly property real run: root.height - root.edge * 2
    readonly property real gap: 3
    readonly property real seg: Math.max(2, (root.run - root.gap * 7) / 8)
    readonly property real mid: root.height / 2

    Repeater {
        model: 8

        Item {
            id: pair
            required property int index
            readonly property real y0: root.edge + pair.index * (root.seg + root.gap)

            Rectangle {
                x: root.rim + root.band * 0.2
                y: pair.y0
                width: root.band * 0.6
                height: root.seg
                color: W.warm[pair.index]
            }

            Rectangle {
                x: root.width - root.rim - root.band * 0.8
                y: pair.y0
                width: root.band * 0.6
                height: root.seg
                color: W.cold_lit[pair.index]
            }
        }
    }

    Repeater {
        model: [-1, 1]

        Rectangle {
            required property int modelData
            x: root.width / 2 + modelData * 5 - 2
            y: root.rim
            width: 4
            height: root.band - 1
            color: W.white
        }
    }

    Rectangle {
        x: root.width / 2 - 2.5
        y: root.height - root.rim - root.band + 1
        width: 5
        height: root.band - 1
        color: W.white
    }

    Repeater {
        model: [[0, 0], [1, 0], [0, 1], [1, 1]]

        Rectangle {
            required property var modelData
            readonly property real d: Math.max(4, root.band - 2)
            x: modelData[0] ? root.width - root.rim - 1 - d : root.rim + 1
            y: modelData[1] ? root.height - root.rim - 1 - d : root.rim + 1
            width: d
            height: d
            radius: d / 2
            color: W.white
        }
    }

    Watch.PanelShape {
        x: root.edge
        y: root.edge
        width: root.width - root.edge * 2
        height: root.height - root.edge * 2
        cut: 12
        notch_w: root.band
        notch_h: 20
        top_color: root.st.lcd_top
        bottom_color: root.st.lcd_bottom
    }
}
