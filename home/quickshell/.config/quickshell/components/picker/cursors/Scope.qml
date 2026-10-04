// home/quickshell/.config/quickshell/components/picker/cursors/Scope.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"

// MGS binocular reticle for the PS1 picker skin: gapped full-screen hairlines, a box reticle
// with a small aim crosshair, and X/Y readouts at the line ends.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property bool target_mode

    property point at: Screenshot.cursor_point
    property bool shown: Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name
    readonly property int cx: Math.round(root.at.x)
    readonly property int cy: Math.round(root.at.y)
    readonly property int gx: Math.round(root.origin.x + root.at.x)
    readonly property int gy: Math.round(root.origin.y + root.at.y)
    readonly property color hud: Style.picker_hud
    property int box_w: 58
    property int box_h: 38
    readonly property int h_gap: Math.max(34, root.box_w / 2 + 5)
    readonly property int v_gap: Math.max(24, root.box_h / 2 + 5)

    visible: Style.picker_skin === "scope" && root.shown && !root.target_mode

    Rectangle {
        x: 0
        y: root.cy
        width: Math.max(0, root.cx - root.h_gap)
        height: 1
        color: Qt.alpha(root.hud, 0.55)
    }

    Rectangle {
        x: root.cx + root.h_gap
        y: root.cy
        width: Math.max(0, root.width - x)
        height: 1
        color: Qt.alpha(root.hud, 0.55)
    }

    Rectangle {
        x: root.cx
        y: 0
        width: 1
        height: Math.max(0, root.cy - root.v_gap)
        color: Qt.alpha(root.hud, 0.55)
    }

    Rectangle {
        x: root.cx
        y: root.cy + root.v_gap
        width: 1
        height: Math.max(0, root.height - y)
        color: Qt.alpha(root.hud, 0.55)
    }

    Rectangle {
        x: root.cx - Math.floor(root.box_w / 2)
        y: root.cy - Math.floor(root.box_h / 2)
        width: root.box_w
        height: root.box_h
        color: "transparent"
        border.width: 2
        border.color: root.hud
    }

    Rectangle {
        x: root.cx - 2
        y: root.cy
        width: 5
        height: 1
        color: root.hud
    }

    Rectangle {
        x: root.cx
        y: root.cy - 2
        width: 1
        height: 5
        color: root.hud
    }

    Text {
        id: lbl_x
        text: "X " + root.gx
        color: root.hud
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        style: Text.Raised
        styleColor: Style.text_shadow
        x: root.cx < root.width - 90 ? root.width - lbl_x.implicitWidth - 10 : 8
        y: root.cy > lbl_x.implicitHeight + 8 ? root.cy - lbl_x.implicitHeight - 4 : root.cy + 4
    }

    Text {
        id: lbl_y
        text: "Y " + root.gy
        color: root.hud
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        style: Text.Raised
        styleColor: Style.text_shadow
        x: root.cx + 6
        y: root.cy < root.height - 60 ? root.height - lbl_y.implicitHeight - 6 : 32
    }
}
