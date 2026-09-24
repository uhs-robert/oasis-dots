// home/quickshell/.config/quickshell/components/CardRule.qml
import QtQuick
import "../theme"

// An open card: a 1px rule down the left edge, with a fading sweep while selected.
Item {
    id: root

    property var st: Style.for_item(root)
    property bool selected: false

    anchors.fill: parent

    FadeFill {
        visible: root.selected
        fill: Qt.alpha(root.st.caret_color, 0.09)
    }

    Rectangle {
        width: 1
        height: parent.height
        color: root.selected ? root.st.caret_color : root.st.hairline_dim
    }
}
