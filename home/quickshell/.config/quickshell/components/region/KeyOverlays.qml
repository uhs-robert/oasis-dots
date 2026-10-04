// home/quickshell/.config/quickshell/components/region/KeyOverlays.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../services"
import ".."

// The key help box and the key hint bar.
Item {
    id: root

    required property bool keyboard_owner
    required property bool help_open
    required property bool sharing
    required property bool pixel_mode
    required property bool target_mode
    required property string delay_label

    readonly property string tier_keys: "hjkl move 10px · H/J/K/L move 100px · C-hjkl move 1px · C-H/J/K/L move 300px"
    readonly property string help_text: Screenshot.phase === "toolbar" ? "h/l move · Tab/S-Tab next/prev · c copy · s save · a annotate · o ocr · t scroll text · i scroll image · r record" + (Screenshot.frozen ? "" : " · d delay off/3s/5s/10s") + " · Enter run · Esc/Backspace adjust selection · q cancel" : root.pixel_mode ? root.tier_keys + " · Enter pick · click pick · m loupe · i/o or +/- zoom · [/] loupe size · q/Esc cancel" : root.target_mode ? "hjkl nearest " + Screenshot.mode + " · Tab/S-Tab cycle · d delay off/3s/5s/10s · Enter pick · click pick · m loupe · i/o or +/- zoom · [/] loupe size · q/Esc cancel" : root.tier_keys + " · space anchor, then confirm · v set or drop anchor · O swap ends · drag select · Enter confirm, whole screen without a selection · m loupe · i/o or +/- zoom · [/] loupe size · Esc drop anchor, then " + (root.sharing ? "back to the share overview · q cancel the share" : "cancel · q cancel")

    signal back()

    function focus_help() {
        key_help.forceActiveFocus();
    }

    anchors.fill: parent

    Rectangle {
        id: help_box
        visible: root.keyboard_owner && root.help_open
        z: 3
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, Style.px(520))
        height: Math.min(parent.height - 160, Style.px(440))
        radius: Style.frame_radius
        color: Style.frame_color
        border.width: Style.frame_border_width
        border.color: Style.frame_border_color

        MouseArea {
            anchors.fill: parent
        }

        Rectangle {
            width: parent.width
            height: Style.accent_height
            color: Style.accent_color
            topLeftRadius: help_box.radius
            topRightRadius: help_box.radius
        }

        Text {
            id: help_title
            x: 16
            y: 10 + Style.accent_height
            text: Style.title_text("Screenshot keys", Style)
            color: Style.title_fg
            font.family: Style.title_font_family
            font.pixelSize: Style.fs(-2)
        }

        KeyHelp {
            id: key_help
            anchors.fill: parent
            anchors.topMargin: help_title.y + help_title.height + 8
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottomMargin: 12
            popup_keys: false
            text: root.help_text
            onBack: root.back()
        }
    }

    Rectangle {
        id: hint_box
        visible: root.keyboard_owner
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        width: Math.min(parent.width - 32, hint.implicitWidth + 24)
        height: hint.implicitHeight + 12
        radius: Style.frame_radius
        color: Style.frame_color
        border.width: Style.frame_border_width
        border.color: Style.frame_border_color

        MenuFooter {
            id: hint
            anchors.centerIn: parent
            width: Math.min(implicitWidth, root.width - 56)
            wrap: false
            text: (root.sharing ? "Share region · " : "") + (root.target_mode && Screenshot.phase === "select" ? "hjkl/Tab " + Screenshot.mode + " · d " + root.delay_label.toLowerCase() + " · Enter pick · Esc cancel" : root.pixel_mode ? "hjkl move · Enter pick · m loupe · i/o zoom · Esc cancel" : Screenshot.phase === "toolbar" ? "h/l move · Enter run · c copy · s save · a annotate · o ocr · t scroll text · i scroll image · r record" + (Screenshot.frozen ? "" : " · d delay") + " · Esc/Backspace adjust · q cancel" : Screenshot.anchored ? "hjkl extend · O swap ends · v/Esc drop anchor · Space/Enter " + (Screenshot.preset !== "" ? Screenshot.preset : "confirm") : "drag/hjkl cursor · v/space anchor · Enter full screen · m loupe · i/o zoom · " + (root.sharing ? "Esc back · q cancel" : "Esc cancel")) + " · ? help"
        }
    }
}
