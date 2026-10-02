// home/quickshell/.config/quickshell/components/DeviceShell.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "gameboy" as Gameboy

// A Game Boy around a small popup: the style's model draws the shell and controls, this the pixel screen.
Item {
    id: root

    property var st: Style.for_item(root)
    // Room the popup keeps clear of its content at each side, above the title and below the footer.
    property int room_side: 20
    property int room_top: 30
    property int room_bottom: 80

    readonly property int screen_top: root.room_top - 4
    readonly property int screen_bottom: root.height - root.room_bottom - 4
    readonly property int pad_top: root.height - root.room_bottom + 6

    Loader {
        anchors.fill: parent
        sourceComponent: root.st.device_model === "sp" ? sp : root.st.device_model === "color" ? color : dmg
    }

    Component {
        id: dmg

        Gameboy.ShellDmg {
            screen_top: root.screen_top
            pad_top: root.pad_top
        }
    }

    Component {
        id: color

        Gameboy.ShellColor {
            screen_top: root.screen_top
            pad_top: root.pad_top
        }
    }

    Component {
        id: sp

        Gameboy.ShellSp {
            screen_top: root.screen_top
            pad_top: root.pad_top
        }
    }

    Rectangle {
        id: screen
        x: root.room_side - 4
        y: root.screen_top
        width: parent.width - x * 2
        height: Math.max(0, root.screen_bottom - root.screen_top)
        color: root.st.shade_1
        clip: true

        // The dot matrix: a gap of the off shade between pixels.
        Image {
            visible: root.st.screen_light
            anchors.fill: parent
            fillMode: Image.Tile
            smooth: false
            source: "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='3' height='3'><path d='M2 0h1v3h-1zM0 2h2v1h-2z' fill='" + root.st.shade_0 + "'/></svg>")
        }

        PixelBox {
            anchors.fill: parent
            rings: [root.st.shade_0, root.st.shade_2, root.st.shade_0]
        }
    }
}
