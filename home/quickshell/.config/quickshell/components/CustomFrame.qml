// home/quickshell/.config/quickshell/components/CustomFrame.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "oasis" as Oasis

// The style's own frame shape (OctagonFrame, ChamferFrame, PixelFrame, WindowGradient, SlantFrame) and FrameTicks, each loaded only when its token is set.
Item {
    id: root

    property var st: Style.for_item(root)
    property color octagon_edge: root.st.frame_border_color
    property color chamfer_edge: root.st.frame_border_color
    property real octagon_cut: root.st.frame_octagon
    property bool struts: true
    // Set while a DeviceShell draws the frame instead.
    property bool device: false
    // The frame's outer radii; the window gradient sits inside its border.
    property real top_radius: root.parent && typeof root.parent.radius === "number" ? root.parent.radius : 0
    property real bottom_radius: root.top_radius

    Loader {
        anchors.fill: parent
        anchors.margins: root.st.frame_border_width
        active: root.st.window_gradient.length > 0
        sourceComponent: WindowGradient {
            top_radius: Math.max(0, root.top_radius - root.st.frame_border_width)
            bottom_radius: Math.max(0, root.bottom_radius - root.st.frame_border_width)
        }
    }

    Loader {
        anchors.fill: parent
        active: root.st.frame_cut > 0
        sourceComponent: ChamferFrame {
            border_color: root.chamfer_edge
        }
    }

    Loader {
        anchors.fill: parent
        active: root.st.slant_frame && !root.device
        sourceComponent: Oasis.SlantFrame {
            edge_color: root.chamfer_edge
        }
    }

    Loader {
        anchors.fill: parent
        active: root.st.frame_octagon > 0
        sourceComponent: OctagonFrame {
            cut: root.octagon_cut
            edge_color: root.octagon_edge
            strut_color: root.struts ? root.st.frame_struts : "transparent"
        }
    }

    Loader {
        anchors.fill: parent
        active: root.st.pixel_border.a > 0 && !root.device
        sourceComponent: PixelFrame {
            middle: Qt.colorEqual(root.chamfer_edge, root.st.frame_border_color) ? root.st.pixel_border : root.st.shade_3
        }
    }

    Loader {
        anchors.fill: parent
        active: root.st.frame_ticks !== ""
        sourceComponent: FrameTicks {}
    }
}
