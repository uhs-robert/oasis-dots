// home/quickshell/.config/quickshell/overview/ScopeAim.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../components"
import "../components/picker"
import "../theme"
import "../services"

// The PS1 screenshot scope drawn over the overview's selected window: hairlines, box, ticks and MGS readouts.
Item {
    id: root

    // Target in this item's coordinates: { x, y, w, h }, or null to hide.
    property var aim: null
    property string cls: ""
    property string place: ""
    // Real window geometry for the readouts: { x, y, w, h }.
    property var real: null
    property bool glide: false

    readonly property color hud: Style.picker_hud
    property real tx: root.aim ? root.aim.x : 0
    property real ty: root.aim ? root.aim.y : 0
    property real tw: root.aim ? root.aim.w : 0
    property real th: root.aim ? root.aim.h : 0
    readonly property real cx: Math.round(root.tx + root.tw / 2)
    readonly property real cy: Math.round(root.ty + root.th / 2)

    visible: Style.overview_skin === "scope" && !!root.aim

    Behavior on tx {
        enabled: root.glide
        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
    Behavior on ty {
        enabled: root.glide
        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
    Behavior on tw {
        enabled: root.glide
        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
    Behavior on th {
        enabled: root.glide
        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }

    Rectangle {
        x: 0
        y: root.cy
        width: Math.max(0, root.tx - 10)
        height: 1
        color: Qt.alpha(root.hud, 0.5)
    }

    Rectangle {
        x: root.tx + root.tw + 10
        y: root.cy
        width: Math.max(0, root.width - x)
        height: 1
        color: Qt.alpha(root.hud, 0.5)
    }

    Rectangle {
        x: root.cx
        y: 0
        width: 1
        height: Math.max(0, root.ty - 10)
        color: Qt.alpha(root.hud, 0.5)
    }

    Rectangle {
        x: root.cx
        y: root.ty + root.th + 10
        width: 1
        height: Math.max(0, root.height - y)
        color: Qt.alpha(root.hud, 0.5)
    }

    Rectangle {
        x: root.tx - 2
        y: root.ty - 2
        width: root.tw + 4
        height: root.th + 4
        color: "transparent"
        border.width: 2
        border.color: root.hud
    }

    CornerBrackets {
        x: root.tx - 8
        y: root.ty - 8
        width: root.tw + 16
        height: root.th + 16
        color: root.hud
        inset: 0
        arm: Math.min(14, Math.max(6, Math.min(root.tw, root.th) / 3))
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
        model: root.th >= 140 ? 11 : 0

        Rectangle {
            required property int index
            x: root.tx + root.tw - 10
            y: root.cy - 55 + index * 11
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
        target: scope_text
        from: scope_icon
    }

    LabelPlate {
        target: x_text
    }

    LabelPlate {
        target: y_text
    }

    Text {
        id: header_text
        x: root.tx + 4
        y: root.ty - 22 >= 2 ? root.ty - 22 : root.ty + 8
        text: "- TARGET - -  " + root.cls + " -"
        color: root.hud
        font.family: Style.font_family
        font.pixelSize: Style.fs(-6)
        style: Text.Raised
        styleColor: Style.text_shadow
    }

    Text {
        id: size_text
        readonly property bool below: root.ty + root.th + 8 <= root.height - 20
        readonly property real base_y: size_text.below ? root.ty + root.th + 8 : root.ty + root.th - 24
        // Too narrow for both readouts on one row: the size steps a row away from the target.
        readonly property bool crowded: scope_text.x + scope_text.implicitWidth + 8 > size_text.x
        visible: !!root.real
        x: root.tx + root.tw - 4 - size_text.implicitWidth
        y: size_text.base_y + (size_text.crowded ? (size_text.below ? 1 : -1) * (size_text.implicitHeight + 4) : 0)
        text: root.real ? Math.round(root.real.w) + " x " + Math.round(root.real.h) : ""
        color: root.hud
        font.family: Style.font_family
        font.pixelSize: Style.fs(-6)
        style: Text.Raised
        styleColor: Style.text_shadow
    }

    Binoculars {
        id: scope_icon
        x: root.tx + 4
        y: size_text.base_y - 1
        color: Theme.red
    }

    Text {
        id: scope_text
        x: root.tx + 4 + 32
        y: size_text.base_y - 1
        text: root.place
        color: Style.text_fg
        font.family: Style.font_family
        font.pixelSize: Style.fs(-6)
        style: Text.Raised
        styleColor: Style.text_shadow
    }

    Text {
        id: x_text
        visible: !!root.real && root.width - (root.tx + root.tw) > 90
        x: root.width - x_text.implicitWidth - 6
        y: root.cy - 18
        text: root.real ? "X " + Math.round(root.real.x) : ""
        color: root.hud
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        style: Text.Raised
        styleColor: Style.text_shadow
    }

    Text {
        id: y_text
        visible: !!root.real && root.height - (root.ty + root.th) > 44
        x: root.cx + 6
        y: root.height - 20
        text: root.real ? "Y " + Math.round(root.real.y) : ""
        color: root.hud
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        style: Text.Raised
        styleColor: Style.text_shadow
    }
}
