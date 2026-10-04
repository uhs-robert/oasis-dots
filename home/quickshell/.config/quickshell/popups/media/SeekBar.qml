// home/quickshell/.config/quickshell/popups/media/SeekBar.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../components/ps2" as Ps2
import "../../components/goldeneye" as Goldeneye
import "../../theme"
import "../../services"
import "../snes" as Snes

// Progress bar and knob; click or drag to seek the given player.
Item {
    id: root

    property var player: null

    Layout.fillWidth: true
    Layout.preferredHeight: root.sound_test ? 30 : 16

    readonly property bool sound_test: Style.console_views === "snes"
    readonly property real track_length: MediaState.length_of(root.player)
    readonly property bool has_length: track_length > 0
    readonly property real ratio: root.has_length
        ? Math.max(0, Math.min(1, root.player.position / root.track_length)) : 0
    readonly property bool knob_active: seek_area.containsMouse || seek_area.pressed

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: Style.radius(3)
        color: Style.pal.bg_surface
        visible: root.has_length && !Style.segmented_levels && !root.sound_test
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * root.ratio
        height: 6
        radius: Style.radius(3)
        color: Style.pal.primary
        visible: root.has_length && !Style.segmented_levels && !root.sound_test
    }

    Meter {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.has_length && Style.segmented_levels && !progress_art.item && !Style.track_bars
        segment_count: 40
        implicitHeight: Style.console_views === "nes" ? 16 : Style.px(8)
        value: root.ratio
    }

    Goldeneye.BarRow {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.px(12)
        visible: root.has_length && Style.track_bars
        value: root.ratio
    }

    // Console progress art; its track_x/track_width, when set, bound the seek area.
    Loader {
        id: progress_art
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.sound_test ? parent.height : implicitHeight
        visible: root.has_length || root.sound_test
        sourceComponent: ({ snes: snes_progress, ps2: ps2_progress })[Style.console_views] || null
    }

    Component {
        id: snes_progress
        Snes.SnesSoundTest {
            ratio: root.ratio
            track: root.player && root.player.metadata ? String(root.player.metadata["xesam:trackNumber"] || "") : ""
        }
    }

    Component {
        id: ps2_progress
        Ps2.SphereTrack {
            sphere: Style.px(8)
            value: root.ratio
        }
    }

    Rectangle {
        id: knob
        readonly property int base_size: 12
        width: root.knob_active ? base_size + 3 : base_size
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(parent.width - width, parent.width * root.ratio - width / 2))
        color: Style.pal.primary
        visible: root.has_length && !Style.segmented_levels && !root.sound_test
        opacity: root.knob_active ? 1 : 0
        border.width: 2
        border.color: Style.pal.bg_core

        Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    MouseArea {
        id: seek_area
        readonly property var art: progress_art.item
        x: art && art.track_x !== undefined ? art.track_x : 0
        width: art && art.track_width !== undefined ? art.track_width : parent.width
        height: parent.height
        hoverEnabled: true
        enabled: !!root.player && root.player.canSeek && root.player.positionSupported
        onPressed: mouse => MediaState.seek_ratio(mouse.x / width)
        onPositionChanged: mouse => { if (pressed) MediaState.seek_ratio(Math.max(0, Math.min(1, mouse.x / width))); }
    }
}
