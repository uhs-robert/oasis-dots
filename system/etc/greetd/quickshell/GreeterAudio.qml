// /etc/greetd/quickshell/GreeterAudio.qml
import QtQuick
import QtMultimedia
import Quickshell

// The theme pack's music loop the bar syncs into /var/lib/qs-greeter; skins with their own audio never get one.
Scope {
    id: root

    readonly property string file: Greeter.settings.music_file || ""
    readonly property real level: Math.max(0, Math.min(1, parseFloat(Greeter.settings.music_volume || "0.5") || 0))
    readonly property bool wanted: Greeter.settings.theme_music === "on" && Greeter.settings.lock_music !== "off" && root.file !== "" && !Greeter.granted

    MediaPlayer {
        id: player
        source: root.wanted ? "file:///var/lib/qs-greeter/" + root.file : ""
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            volume: root.level * 0.6
        }
        onMediaStatusChanged: {
            if (player.mediaStatus === MediaPlayer.LoadedMedia && root.wanted) player.play();
        }
        onSourceChanged: {
            if (player.source.toString() === "") player.stop();
        }
    }
}
