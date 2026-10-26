import QtQuick
import qs.theme
import qs.features.media
import "MediaText.js" as MediaText

// The track position as "elapsed / length" over a thin progress line; view only. Polls only while visible.
Item {
    id: root

    property var player: MediaState.active
    property color color: Style.bar_fg
    property font font

    readonly property real length: MediaState.length_of(root.player)
    readonly property real position: root.player ? root.player.position : 0
    readonly property bool watching: root.visible && root.width > 0

    // Only the progress line, for the strip under the clock island where text has no room.
    property bool line_only: false

    implicitWidth: root.line_only ? 0 : label.implicitWidth
    implicitHeight: root.line_only ? 3 : label.implicitHeight + 4

    PositionViewer { active: root.watching && MediaState.playing }

    Text {
        id: label
        visible: !root.line_only
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        text: MediaText.format_time(root.position) + (root.length > 0 ? " / " + MediaText.format_time(root.length) : "")
        color: root.color
        font: root.font
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 2
        radius: 1
        color: Qt.alpha(Theme.theme_primary, 0.25)

        Rectangle {
            width: parent.width * MediaText.ratio(root.position, root.length)
            height: parent.height
            radius: 1
            color: Theme.theme_primary
        }
    }
}
