// /etc/greetd/quickshell/GreeterAudio.qml
import QtQuick
import QtMultimedia
import Quickshell

// The theme pack's music loop the bar syncs into /var/lib/qs-greeter; skins with their own audio never get one.
Scope {
    id: root

    readonly property string file: Greeter.settings.music_file || ""
    readonly property real level: Greeter.level_setting(Greeter.settings.music_volume)
    readonly property bool wanted: Greeter.settings.theme_music === "on" && Greeter.settings.lock_music !== "off" && root.file !== "" && !Greeter.granted

    MediaPlayer {
        id: player
        source: root.wanted ? "file://" + Greeter.data_dir + "/" + root.file : ""
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            volume: root.level
        }
        onMediaStatusChanged: {
            if (player.mediaStatus === MediaPlayer.LoadedMedia && root.wanted) player.play();
        }
        onSourceChanged: {
            if (player.source.toString() === "") player.stop();
        }
    }
}
