// home/quickshell/.config/quickshell/components/TooltipShelf.qml
import QtQuick
import "../services"

// The hovered module's tooltip, dropped under its island in the popup frame.
Popup {
    id: root

    passive: true
    title: Tooltip.title
    body_height: body_text.implicitHeight + 16

    Text {
        id: body_text
        x: 12
        y: 8
        width: parent.width - 24
        text: Tooltip.text
        wrapMode: Text.Wrap
        maximumLineCount: 12
        elide: Text.ElideRight
        color: root.st.text_fg
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-1)
        lineHeight: 1.1
    }
}
