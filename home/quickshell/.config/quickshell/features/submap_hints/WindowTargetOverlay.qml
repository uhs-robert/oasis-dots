pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.ui.frames
import "../../ui/frames/Corners.js" as Corners

// While a `targets` submap (Windows, Resize, Move) is up, frames the window its keys act on and marks each selected one
// with its number, on every screen. Display only: no keyboard, and an empty input mask lets every click through.
PanelWindow {
    id: root

    required property var modelData
    readonly property var windows: WindowTargetState.active ? WindowTargetState.windows_on(root.modelData) : []
    // Follows the window corners Hyprland draws while the Corner style is sent; a chamfer or pixel corner is left
    // square, which the corner brackets cover.
    readonly property real window_radius: Style.corner_sent && Style.corner_profile.corner === "round" ? Corners.fit("round", Style.corner_profile.radius, 0).radius : 0
    readonly property color focus_color: Style.accent_color
    readonly property color selected_color: Style.pal.warning
    // A dark rim beside each line keeps it readable over light and dark windows alike.
    readonly property color rim_color: Qt.rgba(0, 0, 0, 0.5)

    screen: root.modelData
    visible: WindowTargetState.active
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-window-targets"
    // Top, not Overlay: Hyprland stacks a level's layers by when they mapped, and this maps on the same submap change as
    // the hint bar, which it would then cover half the time.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Repeater {
        model: root.windows

        delegate: Item {
            id: target

            required property var modelData
            readonly property bool focused: target.modelData.address === WindowTargetState.focused_address
            readonly property int number: WindowTargetState.selection_number(target.modelData.address)
            readonly property real arm: Math.max(16, Math.min(48, Math.min(target.width, target.height) / 5))

            x: target.modelData.x
            y: target.modelData.y
            width: target.modelData.w
            height: target.modelData.h
            visible: target.focused || target.number > 0

            // Selected: a tint over the window and a line inset from its edge, so the focus frame on the edge stays clear
            // of it when a window is both.
            Rectangle {
                visible: target.number > 0
                anchors.fill: parent
                anchors.margins: 6
                radius: Math.max(0, root.window_radius - 6)
                color: Qt.rgba(root.selected_color.r, root.selected_color.g, root.selected_color.b, 0.14)
                border.width: 3
                border.color: root.selected_color
            }

            Rectangle {
                visible: target.number > 0
                anchors.fill: parent
                anchors.margins: 9
                radius: Math.max(0, root.window_radius - 9)
                color: "transparent"
                border.width: 1
                border.color: root.rim_color
            }

            // Focused: a line on the window's edge with heavy corner brackets, the look of a target lock.
            Rectangle {
                visible: target.focused
                anchors.fill: parent
                radius: root.window_radius
                color: "transparent"
                border.width: 2
                border.color: root.focus_color
            }

            Rectangle {
                visible: target.focused
                anchors.fill: parent
                anchors.margins: 2
                radius: Math.max(0, root.window_radius - 2)
                color: "transparent"
                border.width: 1
                border.color: root.rim_color
            }

            CornerBrackets {
                visible: target.focused
                anchors.fill: parent
                all_corners: true
                inset: 0
                arm: target.arm
                thickness: 5
                color: root.focus_color
            }

            // The selection number, in the order the windows were picked; kept on screen when the window starts off it.
            Rectangle {
                id: badge
                visible: target.number > 0
                x: Math.max(14, 14 - target.x)
                y: Math.max(14, 14 - target.y)
                width: Math.max(height, number_text.implicitWidth + 14)
                height: number_text.implicitHeight + 6
                radius: Style.radius(4)
                color: root.selected_color
                border.width: 1
                border.color: root.rim_color

                Text {
                    id: number_text
                    anchors.centerIn: parent
                    text: String(target.number)
                    color: Style.pal.bg_crust
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(2)
                    font.bold: true
                }
            }
        }
    }
}
