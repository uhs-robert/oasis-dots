// home/quickshell/.config/quickshell/components/picker/targets/Nvimfloat.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../../neovim" as Nvim

// Neovim dressing for the window/screen/region target: window-picker letter tiles, a float with a
// winbar on the pick, a tabline of outputs, and a visual-block highlight for regions.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property rect sel
    required property bool mine
    required property bool target_mode

    readonly property bool full: Screenshot.mode === "screen"
    readonly property bool region: Screenshot.mode === "region"
    readonly property string cls: root.full ? root.screen_name : (Screenshot.targets[Screenshot.target_index] ? Screenshot.targets[Screenshot.target_index].label : "")
    readonly property real tx: root.sel.x
    readonly property real ty: root.sel.y
    readonly property real tw: root.sel.width
    readonly property real th: root.sel.height
    readonly property int inset: root.full ? 6 : 0
    readonly property real fx: root.tx + root.inset
    readonly property real fy: root.ty + root.inset
    readonly property real fw: root.tw - root.inset * 2
    readonly property real fh: root.th - root.inset * 2

    Repeater {
        model: root.target_mode && !root.full ? Screenshot.targets : []

        Item {
            id: tile
            required property var modelData
            required property int index
            readonly property bool picked: tile.index === Screenshot.target_index
            readonly property string letter: Style.picker_hint_keys.length > tile.index ? Style.picker_hint_keys[tile.index] : ""
            visible: tile.modelData.screen === root.screen_name && Screenshot.phase === "select"
            x: tile.modelData.rect.x + tile.modelData.rect.width / 2 - 32
            y: tile.modelData.rect.y + tile.modelData.rect.height / 2 - 32
            width: 64
            height: 64

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: tile.picked ? Theme.theme_secondary : Theme.bg_crust
                border.width: 1
                border.color: tile.picked ? Theme.theme_secondary : Theme.theme_primary
            }

            Text {
                anchors.centerIn: parent
                text: tile.letter
                color: tile.picked ? Theme.bg_crust : Theme.theme_primary
                font.family: Style.mono_font
                font.bold: true
                font.pixelSize: 36
            }
        }
    }

    Item {
        id: target_visuals
        visible: root.mine && root.target_mode
        anchors.fill: parent

        Nvim.FloatFrame {
            fill: "transparent"
            x: root.fx
            y: root.fy
            width: root.fw
            height: root.fh
            title: root.cls
            status: Math.round(root.tw) + "x" + Math.round(root.th)
        }

        Rectangle {
            visible: !root.full
            x: root.fx + 8
            y: root.fy + 10
            width: winbar_text.implicitWidth + 12
            height: winbar_text.implicitHeight + 4
            color: Theme.bg_crust

            Text {
                id: winbar_text
                anchors.centerIn: parent
                text: root.cls + " › " + Math.round(root.fx) + "," + Math.round(root.fy)
                color: Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
            }
        }

        Row {
            visible: root.full
            x: root.fx + 6
            y: root.fy + root.fh - height - 6
            spacing: 0

            Repeater {
                model: Screenshot.mode === "screen" ? Screenshot.targets : []

                Rectangle {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property bool current: tab.index === Screenshot.target_index
                    width: tab_text.implicitWidth + 16
                    height: tab_text.implicitHeight + 6
                    color: tab.current ? Theme.theme_primary : Theme.bg_mantle

                    Text {
                        id: tab_text
                        anchors.centerIn: parent
                        text: Style.picker_hint_keys.charAt(tab.index) + " " + tab.modelData.label
                        color: tab.current ? Theme.bg_crust : Theme.fg_muted
                        font.family: Style.font_family
                        font.bold: tab.current
                        font.pixelSize: Style.fs(-6)
                    }
                }
            }
        }
    }

    Item {
        id: region_visuals
        visible: root.region && root.mine
        anchors.fill: parent

        Rectangle {
            x: root.tx
            y: root.ty
            width: root.tw
            height: root.th
            color: Qt.alpha(Theme.ui_visual_bg, 0.7)
            border.width: 1
            border.color: Qt.alpha(Theme.magenta, 0.55)
        }

        Rectangle {
            x: 0
            y: parent.height - height
            width: vb_msg.implicitWidth + 16
            height: vb_msg.implicitHeight + 6
            color: Theme.bg_crust

            Text {
                id: vb_msg
                anchors.centerIn: parent
                text: "-- VISUAL BLOCK --"
                color: Theme.magenta
                font.family: Style.font_family
                font.bold: true
                font.pixelSize: Style.fs(-3)
            }
        }

        Rectangle {
            anchors.right: parent.right
            y: parent.height - height
            width: showcmd.implicitWidth + 16
            height: showcmd.implicitHeight + 6
            color: Theme.bg_crust

            Text {
                id: showcmd
                anchors.centerIn: parent
                text: Math.round(root.th) + "x" + Math.round(root.tw)
                color: Theme.fg_core
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-3)
            }
        }
    }
}
