import QtQuick
import qs.ui.keys

// The plate the hint bar sits on, at the screen edge the bar is not on. A plain Rectangle so the harness can place it in an Item.
HintPlate {
    id: root
    property bool on_top: false
    property bool carrying: false
    property bool vertical: false

    anchors.horizontalCenter: parent.horizontalCenter
    // y rather than top/bottom anchors: flipping them between undefined and a parent edge left both set and stretched the plate.
    y: root.on_top ? 24 : parent.height - root.height - 24
    width: Math.min(parent.width - 32, root.implicitWidth)
    height: root.implicitHeight
    HintContent {
        anchors.centerIn: parent
        carrying: root.carrying
        vertical: root.vertical
    }
}
