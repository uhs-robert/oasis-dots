// home/quickshell/.config/quickshell/components/CustomFrame.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

// The style's own frame shape (OctagonFrame, ChamferFrame) and FrameTicks, each loaded only when its token is set.
Item {
    id: root

    property var st: Style.for_item(root)
    property color octagon_edge: root.st.frame_border_color
    property color chamfer_edge: root.st.frame_border_color
    property real octagon_cut: root.st.frame_octagon
    property bool struts: true

    Loader {
        anchors.fill: parent
        active: root.st.frame_cut > 0
        sourceComponent: ChamferFrame {
            border_color: root.chamfer_edge
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
        active: root.st.frame_ticks !== ""
        sourceComponent: FrameTicks {}
    }
}
