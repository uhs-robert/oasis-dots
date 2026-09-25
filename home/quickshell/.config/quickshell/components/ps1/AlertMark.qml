// home/quickshell/.config/quickshell/components/ps1/AlertMark.qml
import QtQuick
import "../../theme"

// The MGS alert "!": pops up with an overshoot each time pop() is called.
Item {
    id: root

    property color color: Theme.red
    property real size: 28

    implicitWidth: root.size * 0.8
    implicitHeight: root.size

    function pop() {
        pop_anim.restart();
    }

    Text {
        id: mark
        anchors.centerIn: parent
        text: "!"
        color: root.color
        font.family: Style.font_family
        font.pixelSize: root.size
        font.bold: true
        style: Text.Outline
        styleColor: Theme.bg_shadow
        transformOrigin: Item.Bottom
    }

    SequentialAnimation {
        id: pop_anim
        NumberAnimation { target: mark; property: "scale"; from: 0.2; to: 1.35; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: mark; property: "scale"; to: 1; duration: 120; easing.type: Easing.InOutQuad }
    }
}
