// home/quickshell/.config/quickshell/components/goldeneye/GaugeHeader.qml
import QtQuick
import QtQuick.Layouts

// A popup header: a gauge dial on the left and readout lines filling the right.
Item {
    id: root

    property real value: 0
    property bool muted: false
    property bool low: false
    property string label: ""
    property string readout: ""
    property real size: 100
    default property alias readouts: column.data

    implicitHeight: root.size

    GaugeDial {
        id: dial
        size: root.size
        value: root.value
        muted: root.muted
        low: root.low
        label: root.label
        readout: root.readout
    }

    ColumnLayout {
        id: column
        anchors.left: dial.right
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
    }
}
