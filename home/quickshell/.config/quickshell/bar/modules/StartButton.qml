// home/quickshell/.config/quickshell/bar/modules/StartButton.qml
import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "../../components/neovim" as Neovim

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property Item island: null
    property color island_color: "transparent"
    property int bar_height: 30

    // Styles with a start well seat a smaller logo in a recessed circle.
    readonly property bool well: Style.bar_start_well.a > 0
    readonly property int well_size: root.compact ? 22 : 26
    // Lualine: the button is the HyprVim mode chip, full bar height.
    readonly property bool lualine: Style.bar_lualine

    implicitWidth: root.lualine && chip_loader.item ? chip_loader.item.implicitWidth : root.well ? root.well_size : icon.implicitSize
    implicitHeight: root.lualine ? root.bar_height : root.well ? root.well_size : icon.implicitSize

    Loader {
        id: chip_loader
        active: root.lualine
        anchors.fill: parent
        sourceComponent: Neovim.ModeChip {
            // Start, and Style which drops from it, keep the chip lit while open.
            hovered: hover_handler.hovered || (["start", "style", "lockscreen"].indexOf(Popups.open_name) >= 0 && Popups.open_screen_name === root.screen_name)
            next_bg: { const c = LualineState.first_fill[root.screen_name]; return c && c.a > 0 ? c : Style.bar_side_bg; }
        }
    }

    Rectangle {
        visible: root.well && !root.lualine
        anchors.centerIn: parent
        width: root.well_size
        height: root.well_size
        radius: width / 2
        color: hover_handler.hovered ? Qt.tint(Style.bar_start_well, Qt.alpha(Theme.theme_primary, 0.22)) : Style.bar_start_well
        border.width: 1
        border.color: Qt.alpha(Theme.bg_shadow, 0.3)

        Behavior on color {
            ColorAnimation { duration: 140 }
        }
    }

    // A round focus ring around the well in place of the square hover.
    Rectangle {
        visible: root.well && !root.lualine && opacity > 0
        anchors.centerIn: parent
        width: root.well_size + 5
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1.5
        border.color: Theme.theme_primary
        opacity: hover_handler.hovered ? 0.9 : 0

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        visible: !root.lualine && !root.well
        anchors.fill: parent
        anchors.margins: -6
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    HoverHandler {
        id: hover_handler
    }

    // Load the SVG file directly: the icon provider returns a small raster that blurs when scaled.
    Image {
        id: icon
        visible: !root.lualine
        readonly property int implicitSize: root.well ? root.well_size - 8 : root.compact ? 26 : 30
        readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1

        anchors.centerIn: parent
        width: implicitSize
        height: implicitSize
        sourceSize.width: Math.ceil(implicitSize * dpr)
        sourceSize.height: Math.ceil(implicitSize * dpr)
        source: status === Image.Error ? Quickshell.iconPath("start-here-archlinux", "start-here") : "file:///usr/share/icons/Papirus/64x64/apps/start-here-archlinux.svg"
        smooth: true
        mipmap: true
    }

    onIslandChanged: if (root.island) {
        Popups.register_default("start", root.island, root.island_color, root.screen_name, root);
        Popups.register_default("style", root.island, root.island_color, root.screen_name, root, "start");
        Popups.register_default("lockscreen", root.island, root.island_color, root.screen_name, root, "style");
    }
    Component.onDestruction: {
        Popups.unregister("start", root.screen_name, root);
        Popups.unregister("style", root.screen_name, root);
        Popups.unregister("lockscreen", root.screen_name, root);
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                Quickshell.execDetached(["sh", "-c", "~/.config/hypr/theme/switch.lua"]);
            } else {
                Popups.toggle("start", root.island, root.island_color, root.screen_name);
            }
        }
    }
}
