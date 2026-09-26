// home/quickshell/.config/quickshell/overview/WorkspaceTile.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import "../components"
import "../theme"
import "../services"

// One workspace as a small monitor: its windows at their real places, scaled into the tile.
Item {
    id: root

    property var entry: null
    property bool selected: false
    property string selected_address: ""
    // Carried windows (address -> true), the first one's toplevel for the drop icon, and how many there are.
    property var picked: ({})
    property var picked_toplevel: null
    property int picked_count: 0
    // Marked windows: address -> 1-based mark number.
    property var marks: ({})
    property string swap_address: ""
    property bool drop_target: false
    // Addresses kept bright by the filter; null while nothing is typed.
    property var matches: null
    // Windows capture continuously; otherwise each shows one frame taken as it appears.
    property bool live: false
    property int live_cap: 6
    property bool shown: true

    readonly property bool is_new: !!root.entry && root.entry.is_new
    readonly property var windows: root.entry ? root.entry.windows : []
    readonly property int text_style: Style.glow ? Text.Outline : Style.text_shadow.a > 0 ? Text.Raised : Text.Normal
    readonly property color text_glow: Style.glow ? Qt.alpha(Theme.theme_primary, 0.3) : Style.text_shadow
    readonly property real label_px: Math.max(9, Math.min(Style.fs(-3), root.height * 0.16))

    signal window_clicked(string address)
    signal tile_clicked()

    Rectangle {
        anchors.fill: parent
        radius: Style.radius(6)
        color: root.is_new ? "transparent" : root.selected ? Qt.tint(Theme.bg_crust, Qt.alpha(Style.caret_color, 0.08)) : Theme.bg_crust
        border.width: root.is_new ? 0 : root.selected ? 2 : 1
        border.color: root.drop_target ? Style.text_accent : root.selected ? Style.caret_color : Theme.ui_border
    }

    DashedOutline {
        visible: root.is_new
        anchors.fill: parent
        color: root.drop_target ? Style.text_accent : root.selected ? Style.caret_color : Theme.ui_border
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.tile_clicked()
    }

    Item {
        id: canvas
        anchors.fill: parent
        anchors.margins: 2
        clip: true

        Repeater {
            model: root.windows

            Rectangle {
                id: win
                required property var modelData
                required property int index
                readonly property bool is_selected: root.selected && win.modelData.address === root.selected_address
                readonly property bool is_picked: !!root.picked[win.modelData.address]
                readonly property int mark: root.marks[win.modelData.address] || 0
                readonly property bool is_swap: win.modelData.address === root.swap_address
                readonly property bool dimmed: root.matches !== null && !root.matches[win.modelData.address]

                x: win.modelData.rx * canvas.width
                y: win.modelData.ry * canvas.height
                width: Math.max(4, win.modelData.rw * canvas.width)
                height: Math.max(4, win.modelData.rh * canvas.height)
                z: win.is_selected ? 100 : win.modelData.floating ? 50 + win.index : win.index
                color: Theme.bg_surface
                radius: Style.radius(3)
                border.width: win.is_selected || win.mark > 0 || win.is_swap ? 2 : 1
                border.color: win.is_picked || win.is_swap || (win.mark > 0 && !win.is_selected) ? Style.text_accent : win.is_selected ? Style.caret_color : Qt.alpha(Theme.ui_border, 0.8)
                opacity: win.is_picked ? 0.45 : win.dimmed ? 0.2 : 1
                clip: true

                WindowThumbnail {
                    anchors.fill: parent
                    anchors.margins: win.border.width
                    toplevel: win.modelData.toplevel
                    active: root.shown
                    live: root.live && win.index < root.live_cap
                    icon_size: Math.min(width, height) * 0.45
                }

                CornerBrackets {
                    anchors.fill: parent
                    visible: win.is_selected && color.a > 0
                    color: Style.selection_brackets
                    inset: 2
                    arm: Math.min(10, win.width / 4)
                    all_corners: true
                }

                DashedOutline {
                    visible: win.is_swap
                    anchors.fill: parent
                    anchors.margins: 4
                    color: Style.text_accent
                }

                Rectangle {
                    visible: win.is_swap && win.height >= 20
                    anchors.centerIn: parent
                    width: swap_text.implicitWidth + 10
                    height: swap_text.implicitHeight + 2
                    radius: Style.radius(3)
                    color: Style.text_accent

                    Text {
                        id: swap_text
                        anchors.centerIn: parent
                        text: "SWAP"
                        color: Theme.bg_crust
                        font.family: Style.font_family
                        font.pixelSize: root.label_px
                        font.bold: true
                    }
                }

                Rectangle {
                    visible: win.mark > 0 && win.height >= 16
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 3
                    width: Math.max(height, mark_text.implicitWidth + 8)
                    height: mark_text.implicitHeight + 2
                    radius: Style.radius(height / 2)
                    color: Style.text_accent

                    Text {
                        id: mark_text
                        anchors.centerIn: parent
                        text: "\u2713" + win.mark
                        color: Theme.bg_crust
                        font.family: Style.font_family
                        font.pixelSize: root.label_px
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.window_clicked(win.modelData.address)
                }
            }
        }
    }

    Rectangle {
        id: label_chip
        x: 4
        y: 4
        width: label_text.implicitWidth + 10
        height: label_text.implicitHeight + 2
        radius: Style.radius(3)
        visible: root.height >= 28
        color: root.selected ? Style.caret_color : Qt.alpha(Theme.bg_crust, 0.85)

        Text {
            id: label_text
            anchors.centerIn: parent
            text: root.is_new ? "+ " + (root.entry ? root.entry.name : "") : root.entry ? root.entry.name : ""
            color: root.selected ? Theme.bg_crust : root.entry && root.entry.focused ? Style.text_accent : root.entry && root.entry.shown_on_monitor ? Style.text_primary : Style.text_muted
            font.family: Style.font_family
            font.pixelSize: root.label_px
            font.bold: true
            style: root.selected ? Text.Normal : root.text_style
            styleColor: root.text_glow
        }
    }

    // The window being carried, shown where it would land.
    IconImage {
        visible: root.drop_target && !!root.picked_toplevel
        anchors.centerIn: parent
        implicitSize: Math.min(root.width, root.height) * 0.35
        opacity: 0.8
        asynchronous: true
        source: root.picked_toplevel ? WindowState.icon_for(root.picked_toplevel) : ""

        Rectangle {
            visible: root.picked_count > 1
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.max(height, count_text.implicitWidth + 8)
            height: count_text.implicitHeight + 2
            radius: Style.radius(height / 2)
            color: Style.text_accent

            Text {
                id: count_text
                anchors.centerIn: parent
                text: String(root.picked_count)
                color: Theme.bg_crust
                font.family: Style.font_family
                font.pixelSize: root.label_px
                font.bold: true
            }
        }
    }
}
