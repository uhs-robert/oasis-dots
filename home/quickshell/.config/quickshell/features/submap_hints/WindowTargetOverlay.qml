pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme

// While a `targets` submap (Windows, Resize, Move) is up, numbers each selected window in the order it was picked, on
// every screen. Hyprland draws the selection itself as the window's border (lib/selection.lua); this only adds
// the number. Display only: no keyboard, and an empty input mask lets every click through.
PanelWindow {
    id: root

    required property var modelData
    readonly property var selected_windows: WindowTargetState.active && WindowTargetState.selected.length > 0 ? WindowTargetState.windows_on(root.modelData).filter(w => WindowTargetState.selection_number(w.address) > 0) : []
    // Far enough in from the window's top-left that no corner style (round, chamfer, pixel) cuts into the badge.
    readonly property int inset: 16

    screen: root.modelData
    visible: root.selected_windows.length > 0
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-window-targets"
    // Overlay, so a fullscreen window's number shows too. It maps only while something is selected, and a badge sits at
    // a window's top-left, away from the hint bar it could otherwise stack over.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Repeater {
        model: root.selected_windows

        delegate: Rectangle {
            id: badge

            required property var modelData
            readonly property int number: WindowTargetState.selection_number(badge.modelData.address)

            // Kept on screen when the window starts off it.
            x: Math.max(root.inset, badge.modelData.x + root.inset)
            y: Math.max(root.inset, badge.modelData.y + root.inset)
            width: Math.max(badge.height, number_text.implicitWidth + 14)
            height: number_text.implicitHeight + 6
            radius: Style.radius(4)
            color: Style.pal.secondary
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.5)

            Text {
                id: number_text
                anchors.centerIn: parent
                text: String(badge.number)
                color: Style.pal.bg_crust
                font.family: Style.font_family
                font.pixelSize: Style.fs(2)
                font.bold: true
            }
        }
    }
}
