// home/quickshell/.config/quickshell/components/popup/PopupDecor.qml
import QtQuick
import "../../theme"
import ".."
import "../neovim" as Neovim
import "../goldeneye" as Goldeneye

Item {
    id: root

    required property var st
    required property bool has_title
    required property string shown_title
    required property string title_value
    required property real chip_height
    required property real frame_radius
    required property bool island_capsule
    required property real island_width
    required property real capsule_x
    required property bool dock_bottom
    required property bool device
    required property real room_side
    required property real room_top
    required property real room_bottom
    required property bool lcd
    readonly property real engraving_height: root.st.frame_engraving !== "" ? Math.ceil(engraving_metrics.height) + 4 : 0

    anchors.fill: parent

    Loader {
        anchors.fill: parent
        active: root.st.border_title
        sourceComponent: Neovim.FloatFrame {
            st: root.st
            title: root.has_title ? root.shown_title : ""
            status: root.st.title_status ? root.title_value : ""
            chip_height: root.chip_height
            radius: root.frame_radius
        }
    }

    // Under a capsule the top border gives way, so the capsule's fill runs straight into the frame's.
    Rectangle {
        visible: root.island_capsule && !root.dock_bottom && root.st.frame_border_width > 0
        x: root.capsule_x + root.st.frame_border_width
        width: root.island_width - root.st.frame_border_width * 2
        height: root.st.frame_border_width
        color: root.st.frame_shade.a > 0 ? root.st.frame_shade : root.st.frame_color
    }

    Loader {
        anchors.fill: parent
        active: root.device
        sourceComponent: DeviceShell {
            room_side: root.room_side
            room_top: root.room_top
            room_bottom: root.room_bottom
        }
    }

    // The watch face: a shaded panel with static scan rows, and the engraving on the bezel below it.
    Rectangle {
        id: lcd_panel
        readonly property real edge: root.st.inset_pad + root.st.lcd_margin
        visible: root.lcd && !root.st.frame_watch
        x: lcd_panel.edge
        y: lcd_panel.edge
        width: parent.width - lcd_panel.edge * 2
        height: parent.height - lcd_panel.edge * 2 - root.engraving_height
        radius: root.st.lcd_radius
        border.width: 1
        border.color: root.st.lcd_border
        clip: true
        gradient: Gradient {
            GradientStop { position: 0; color: root.st.lcd_top }
            GradientStop { position: 1; color: root.st.lcd_bottom }
        }

        Scanlines {
            anchors.fill: parent
            color: root.st.lcd_scan
            period: 3
        }

        CornerBrackets {
            anchors.fill: parent
            color: root.st.lcd_brackets
            inset: 5
            arm: 14
            all_corners: true
        }
    }

    Loader {
        anchors.fill: parent
        active: root.st.frame_watch
        sourceComponent: Goldeneye.PopupPanel {
            st: root.st
        }
    }

    Text {
        id: engraving
        visible: root.st.frame_engraving !== ""
        x: lcd_panel.edge + 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.st.inset_pad + 2
        text: root.st.frame_engraving
        color: root.st.frame_border_color
        font.family: Style.title_font_family
        font.pixelSize: 9
        font.letterSpacing: 2.5
    }

    FontMetrics {
        id: engraving_metrics
        font: engraving.font
    }
}
