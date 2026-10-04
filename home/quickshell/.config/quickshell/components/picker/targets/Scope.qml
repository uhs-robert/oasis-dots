// home/quickshell/.config/quickshell/components/picker/targets/Scope.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."
import ".."

// PS1 scope dressing for the window/screen/region target: dashed olive outlines on the rest,
// an olive box with corner ticks, a center +, hairlines to the screen edges, and MGS-style readouts.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property rect sel
    required property bool mine
    required property bool target_mode

    readonly property color hud: Style.picker_hud
    readonly property bool full: Screenshot.mode === "screen"
    readonly property bool region: Screenshot.mode === "region"
    readonly property string cls: root.region ? "AREA" : root.full ? root.screen_name : (Screenshot.targets[Screenshot.target_index] ? Screenshot.targets[Screenshot.target_index].label : "")
    readonly property real tx: root.sel.x
    readonly property real ty: root.sel.y
    readonly property real tw: root.sel.width
    readonly property real th: root.sel.height
    readonly property real cx: root.tx + root.tw / 2
    readonly property real cy: root.ty + root.th / 2
    readonly property int box_inset: root.full ? 6 : -2
    readonly property int tick_o: root.full ? 12 : -8
    readonly property int label_margin: root.full ? 26 : 4

    Repeater {
        model: root.target_mode ? Screenshot.targets : []

        Item {
            id: other
            required property var modelData
            required property int index
            visible: other.modelData.screen === root.screen_name && other.index !== Screenshot.target_index && Screenshot.phase === "select"
            x: other.modelData.rect.x
            y: other.modelData.rect.y
            width: other.modelData.rect.width
            height: other.modelData.rect.height

            DashedOutline {
                anchors.fill: parent
                color: Qt.alpha(root.hud, 0.4)
            }

            LabelPlate {
                target: other_label
            }

            Text {
                id: other_label
                x: 6
                y: 4
                text: other.modelData.label
                color: Qt.alpha(root.hud, 0.55)
                font.family: Style.font_family
                font.pixelSize: Style.fs(-7)
            }
        }
    }

    Item {
        id: target_visuals
        visible: root.mine
        anchors.fill: parent

        Rectangle {
            visible: !root.full
            x: 0
            y: root.cy
            width: Math.max(0, root.tx - 6)
            height: 1
            color: Qt.alpha(root.hud, 0.5)
        }

        Rectangle {
            visible: !root.full
            x: root.tx + root.tw + 6
            y: root.cy
            width: Math.max(0, target_visuals.width - x)
            height: 1
            color: Qt.alpha(root.hud, 0.5)
        }

        Rectangle {
            visible: !root.full
            x: root.cx
            y: 0
            width: 1
            height: Math.max(0, root.ty - 6)
            color: Qt.alpha(root.hud, 0.5)
        }

        Rectangle {
            visible: !root.full
            x: root.cx
            y: root.ty + root.th + 6
            width: 1
            height: Math.max(0, target_visuals.height - y)
            color: Qt.alpha(root.hud, 0.5)
        }

        Rectangle {
            x: root.tx + root.box_inset
            y: root.ty + root.box_inset
            width: root.tw - root.box_inset * 2
            height: root.th - root.box_inset * 2
            color: "transparent"
            border.width: 2
            border.color: root.hud
        }

        CornerBrackets {
            x: root.tx + root.tick_o
            y: root.ty + root.tick_o
            width: root.tw - root.tick_o * 2
            height: root.th - root.tick_o * 2
            color: root.hud
            inset: 0
            arm: 14
            thickness: 2
            all_corners: true
        }

        Rectangle {
            x: root.cx - 5
            y: root.cy
            width: 11
            height: 1
            color: root.hud
        }

        Rectangle {
            x: root.cx
            y: root.cy - 5
            width: 1
            height: 11
            color: root.hud
        }

        Repeater {
            model: 11

            Rectangle {
                required property int index
                x: root.tx + root.tw - (root.full ? 18 : 10)
                y: root.cy - 60 + index * 11
                width: 6
                height: 1
                color: Qt.alpha(root.hud, 0.7)
            }
        }

        LabelPlate {
            target: header_text
        }

        LabelPlate {
            target: size_text
        }

        LabelPlate {
            target: cam_text
            from: cam_icon
        }

        LabelPlate {
            target: x_text
        }

        LabelPlate {
            target: y_text
        }

        Text {
            id: header_text
            x: root.tx + root.label_margin
            y: root.full ? root.ty + 22 : root.ty - 22 >= 2 ? root.ty - 22 : root.ty + 8
            text: "- TARGET - -  " + root.cls + " -"
            color: root.hud
            font.family: Style.font_family
            font.pixelSize: Style.fs(-6)
            style: Text.Raised
            styleColor: Style.text_shadow
        }

        Text {
            id: size_text
            readonly property real base_y: root.full ? root.ty + root.th - 30 : root.ty + root.th + 8 <= target_visuals.height - 20 ? root.ty + root.th + 8 : root.ty + root.th - 24
            x: root.tx + root.tw - root.label_margin - size_text.implicitWidth
            y: size_text.base_y
            text: Math.round(root.tw) + " x " + Math.round(root.th)
            color: root.hud
            font.family: Style.font_family
            font.pixelSize: Style.fs(-6)
            style: Text.Raised
            styleColor: Style.text_shadow
        }

        Binoculars {
            id: cam_icon
            x: root.tx + root.label_margin
            y: size_text.base_y - 1
            color: Theme.red
        }

        Text {
            id: cam_text
            x: root.tx + root.label_margin + 32
            y: size_text.base_y - 1
            text: "CAMERA"
            color: Style.text_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-6)
            style: Text.Raised
            styleColor: Style.text_shadow
        }

        Text {
            id: x_text
            visible: !root.full && target_visuals.width - (root.tx + root.tw) > 90
            x: target_visuals.width - 70
            y: root.cy - 18
            text: "X " + Math.round(root.tx)
            color: root.hud
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
            style: Text.Raised
            styleColor: Style.text_shadow
        }

        Text {
            id: y_text
            visible: !root.full && target_visuals.height - (root.ty + root.th) > 44
            x: root.cx + 6
            y: target_visuals.height - 20
            text: "Y " + Math.round(root.ty)
            color: root.hud
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
            style: Text.Raised
            styleColor: Style.text_shadow
        }
    }
}
