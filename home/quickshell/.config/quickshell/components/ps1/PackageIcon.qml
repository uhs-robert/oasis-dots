// home/quickshell/.config/quickshell/components/ps1/PackageIcon.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"

// A save-block style 5x5 mirrored pixel icon hashed from a name, so each package keeps its own.
Item {
    id: root

    property string name: ""
    property real size: 20

    // real, not int: hashes above 2^31 would wrap to a negative QML int and index colors[] out of range.
    readonly property real hash: {
        let h = 5381;
        for (let i = 0; i < root.name.length; i++) h = ((h * 33) ^ root.name.charCodeAt(i)) >>> 0;
        return h;
    }
    readonly property var colors: [Theme.blue, Theme.green, Theme.yellow, Theme.magenta, Theme.cyan, Theme.red, Theme.bright_yellow]
    readonly property color ink: root.colors[root.hash % root.colors.length]
    readonly property real cell: Math.floor(root.size / 5)

    implicitWidth: root.cell * 5
    implicitHeight: root.cell * 5

    Repeater {
        model: 25

        Rectangle {
            required property int index
            readonly property int col: index % 5
            readonly property int row: Math.floor(index / 5)
            readonly property int bit: row * 3 + (col < 3 ? col : 4 - col)
            visible: ((root.hash >>> 3) >>> bit & 1) === 1
            x: col * root.cell
            y: row * root.cell
            width: root.cell
            height: root.cell
            color: Qt.darker(root.ink, 1 + row * 0.08)
        }
    }
}
