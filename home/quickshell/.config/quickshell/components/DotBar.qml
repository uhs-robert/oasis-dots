// home/quickshell/.config/quickshell/components/DotBar.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

// A low-to-high temperature range as a row of pixel dots on a shared scale; the dot holding the high is brightest.
Row {
    id: root

    property real low: 0
    property real high: 0
    property real scale_min: 0
    property real scale_max: 1
    property int count: 10
    property int dot: 4
    readonly property real step: Math.max(1, Math.ceil((root.scale_max - root.scale_min) / root.count))
    readonly property real start: Math.floor(root.scale_min)

    spacing: 1

    Repeater {
        model: root.count

        Rectangle {
            id: cell
            required property int index
            readonly property real from: root.start + cell.index * root.step
            readonly property bool lit: cell.from + root.step > root.low && cell.from <= root.high
            readonly property bool peak: cell.lit && root.high < cell.from + root.step
            width: root.dot
            height: root.dot
            color: cell.peak ? Style.shade_3 : cell.lit ? Style.shade_2 : Style.shade_0
        }
    }
}
