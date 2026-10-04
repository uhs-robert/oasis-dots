// home/quickshell/.config/quickshell/components/picker/cursors/Scopeitem.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."

// MGS2 scope item reticle for the PS2 picker skin: blue corner brackets around a
// center dot, with a small zero-padded global-X readout above.
Item {
    id: root

    required property string screen_name
    required property point origin
    required property bool target_mode

    property point at: Screenshot.cursor_point
    property bool shown: Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name
    readonly property int cx: Math.round(root.at.x)
    readonly property int cy: Math.round(root.at.y)
    readonly property int box_w: 44
    readonly property int box_h: 30

    function pad4(v) {
        const n = Math.round(v);
        return (n < 0 ? "-" : "") + String(Math.abs(n)).padStart(4, "0");
    }

    visible: Style.picker_skin === "scopeitem" && root.shown && !root.target_mode

    CornerBrackets {
        x: root.cx - root.box_w / 2
        y: root.cy - root.box_h / 2
        width: root.box_w
        height: root.box_h
        color: Theme.blue
        inset: 0
        arm: 10
        thickness: 2
        all_corners: true
    }

    Rectangle {
        x: root.cx - 2
        y: root.cy - 2
        width: 5
        height: 5
        color: Qt.alpha(Theme.bg_shadow, 0.7)
    }

    Rectangle {
        x: root.cx - 1
        y: root.cy - 1
        width: 3
        height: 3
        color: Theme.fg_strong
    }

    Text {
        id: readout
        text: "- " + root.pad4(root.origin.x + root.at.x) + " -"
        color: Theme.blue
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-6)
        style: Text.Raised
        styleColor: Style.text_shadow
        x: root.cx - readout.implicitWidth / 2
        y: root.cy - root.box_h / 2 - readout.implicitHeight - 4
    }
}
