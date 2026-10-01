// home/quickshell/.config/quickshell/components/goldeneye/PopupBezel.qml
import QtQuick
import "../../lock/skins/goldeneye" as Watch
import "../../lock/skins/goldeneye/Watch.js" as W

// The popup frame as the classic watch: curved warm and blue segment arcs, white bars and studs on the bezel, the green octagon panel inside.
Item {
    id: root

    required property var st
    property real edge: root.st.inset_pad + root.st.lcd_margin
    property real rim: root.st.frame_border_width
    readonly property real band: root.edge - root.rim
    readonly property real thick: 5
    readonly property real run: Math.max(30, Math.min(root.height - root.edge * 2 - 8, 8 * 34 + 7 * 3))
    readonly property real sag: Math.min(Math.max(3, root.band - 1 - root.thick - 1), Math.max(4, root.run * 0.1))
    readonly property real arc_w: root.thick / 2 + root.sag / (1 - Math.cos(50 * Math.PI / 180))
    readonly property real arc_h: root.run / 0.72 + root.thick

    Watch.SegmentArc {
        x: root.rim + 1
        y: (root.height - root.arc_h) / 2
        width: root.arc_w
        height: root.arc_h
        thickness: root.thick
        gap: 3
        colors: W.warm
    }

    Watch.SegmentArc {
        x: root.width - root.rim - 1 - root.arc_w
        y: (root.height - root.arc_h) / 2
        width: root.arc_w
        height: root.arc_h
        thickness: root.thick
        gap: 3
        mirror: true
        colors: W.cold_lit
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
