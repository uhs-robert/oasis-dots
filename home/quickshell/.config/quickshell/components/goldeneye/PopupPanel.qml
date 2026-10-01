// home/quickshell/.config/quickshell/components/goldeneye/PopupPanel.qml
import QtQuick
import "../../lock/skins/goldeneye" as Watch

// A popup's content area as the watch's translucent green octagon, inset in the black frame.
Item {
    id: root

    required property var st
    readonly property real edge: root.st.inset_pad + root.st.lcd_margin

    Watch.PanelShape {
        x: root.edge
        y: root.edge
        width: root.width - root.edge * 2
        height: root.height - root.edge * 2
        cut: 12
        notches: false
        top_color: root.st.lcd_top
        bottom_color: root.st.lcd_bottom
    }
}
