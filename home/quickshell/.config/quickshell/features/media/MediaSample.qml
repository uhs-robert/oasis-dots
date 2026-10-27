import QtQuick
import Quickshell.Services.Mpris
import "MediaSample.js" as Logic

// A made-up track for a preview of the media well when `player` has none to show (MediaSample.js): it carries the
// MprisPlayer properties the well reads plus cava-style levels, so the well draws it with its own code and no cava
// process runs for it. It moves only while `running`.
Item {
    id: root

    property var player: MediaState.active
    property bool running: false
    readonly property bool replaces_player: !Logic.uses_live(!!root.player, !!root.player && root.player.isPlaying, !!root.player && root.player.playbackState === MprisPlaybackState.Stopped, root.player ? root.player.trackTitle || "" : "", root.player ? root.player.trackArtist || "" : "")

    // Long enough that the default text width cuts it and scrolling has something to slide.
    readonly property string trackTitle: "Lanterns Over the Harbour (Extended Night Mix)"
    readonly property string trackArtist: "The Quiet Meridian Orchestra"
    readonly property string trackArtUrl: Qt.resolvedUrl("sample-art.svg")
    readonly property string identity: "Sample"
    readonly property bool isPlaying: true
    readonly property bool canTogglePlaying: true
    readonly property bool lengthSupported: true
    readonly property bool positionSupported: true
    readonly property real length: 252
    readonly property var metadata: ({})
    readonly property real position: Logic.position(root.elapsed + 83, root.length)

    readonly property int bar_count: CavaState.bar_count
    readonly property var levels: Logic.levels(root.elapsed, root.bar_count)
    // Already smooth, so the line takes the levels as they are rather than CavaState's rise-and-fall filter.
    readonly property var line_levels: root.levels

    property real elapsed: 0

    visible: false

    Timer {
        interval: 33
        repeat: true
        running: root.running
        onTriggered: root.elapsed += interval / 1000
    }
}
