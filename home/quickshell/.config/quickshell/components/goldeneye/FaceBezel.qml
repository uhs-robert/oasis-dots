// home/quickshell/.config/quickshell/components/goldeneye/FaceBezel.qml
import QtQuick
import "../../lock/skins/goldeneye" as Watch
import "../../lock/skins/goldeneye/Watch.js" as W

// A popup as the whole watch face: a rounded black dial, the warm and blue arcs, white bars and studs, and the green octagon holding the content.
Item {
    id: root

    required property var st
    readonly property real rim: root.st.frame_border_width
    readonly property real px: root.st.lcd_margin + root.st.face_side - 22
    readonly property real py: root.st.lcd_margin + root.st.face_top - 14
    readonly property real pb: root.st.lcd_margin + root.st.face_bottom - 14
    readonly property real cut: 44
    readonly property real thick: 12
    readonly property real sag: Math.max(6, root.px - 8 - root.rim - 3 - root.thick)
    readonly property real run: Math.max(60, Math.min(root.height - 2 * (root.st.face_radius + 10), 8 * 46 + 7 * 6))
    readonly property real arc_w: root.thick / 2 + root.sag / (1 - Math.cos(50 * Math.PI / 180))
    readonly property real arc_h: root.run / 0.72 + root.thick

    Rectangle {
        anchors.fill: parent
        radius: root.st.face_radius
        color: W.black
        border.width: root.rim
        border.color: W.rim
    }

    Watch.SegmentArc {
        x: root.rim + 3
        y: (root.height - root.arc_h) / 2
        width: root.arc_w
        height: root.arc_h
        thickness: root.thick
        gap: 6
        colors: W.warm
    }

    Watch.SegmentArc {
        x: root.width - root.rim - 3 - root.arc_w
        y: (root.height - root.arc_h) / 2
        width: root.arc_w
        height: root.arc_h
        thickness: root.thick
        gap: 6
        mirror: true
        colors: W.cold_lit
    }

    Repeater {
        model: [-1, 1]

        Rectangle {
            required property int modelData
            x: root.width / 2 + modelData * 12 - 5
            y: 4
            width: 10
            height: Math.max(8, root.py - 8)
            color: W.white
        }
    }

    Rectangle {
        x: root.width / 2 - 5
        y: root.height - root.pb + 4
        width: 10
        height: Math.max(8, root.pb - 8)
        color: W.white
    }

    Repeater {
        model: [[0, 0], [1, 0], [0, 1], [1, 1]]

        Rectangle {
            required property var modelData
            x: modelData[0] ? root.width - root.px - 16 - 9 : root.px + 16 - 9
            y: modelData[1] ? root.height - root.pb - 16 - 9 : root.py + 16 - 9
            width: 18
            height: 18
            radius: 9
            color: W.white
        }
    }

    Watch.PanelShape {
        x: root.px
        y: root.py
        width: root.width - root.px * 2
        height: root.height - root.py - root.pb
        cut: root.cut
        notch_w: 10
        notch_h: 28
        top_color: root.st.lcd_top
        bottom_color: root.st.lcd_bottom
    }
}
