// home/quickshell/.config/quickshell/lock/skins/ocarina/OcarinaAudio.qml
import QtQuick
import QtMultimedia
import Qt.labs.folderlistmodel
import Quickshell

// The Ocarina skin's music and sound effects (made by scripts/ocarina-audio): the skin's own audio/ when it holds
// files (the greeter's staged copy), else the user's data dir; a missing file stays silent.
Item {
    id: audio

    // "title", "fairy" or "".
    property string track: ""
    readonly property real music_volume: 0.4
    readonly property real fx_volume: 0.4
    property real title_level: 0
    property real fairy_level: 0
    readonly property string data_dir: "file://" + (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/quickshell/ocarina-audio"
    readonly property bool local_has_files: local_listing.count > 0
    readonly property string base: audio.local_has_files ? Qt.resolvedUrl("audio") : audio.data_dir
    readonly property var files: {
        const out = {};
        const listing = audio.local_has_files ? local_listing : data_listing;
        for (let i = 0; i < listing.count; i++) out[listing.get(i, "fileName")] = true;
        return out;
    }

    function file(name) {
        return audio.files[name] ? audio.base + "/" + name : "";
    }

    function play(name) {
        const fx = ({ start: fx_start, move: fx_move, letter: fx_letter, decide: fx_decide, cancel: fx_cancel, error: fx_error })[name];
        if (fx && fx.status === SoundEffect.Ready) fx.play();
    }

    function sync() {
        const title_on = title_intro.playbackState === MediaPlayer.PlayingState || title_loop.playbackState === MediaPlayer.PlayingState;
        if (audio.track === "title" && !title_on) {
            if (audio.files["title_intro.ogg"]) title_intro.play();
            else title_loop.play();
        }
        const fairy_on = fairy_intro.playbackState === MediaPlayer.PlayingState || fairy_loop.playbackState === MediaPlayer.PlayingState;
        if (audio.track === "fairy" && !fairy_on) {
            if (audio.files["fairy_intro.ogg"]) fairy_intro.play();
            else fairy_loop.play();
        }
        title_fade.restart();
        fairy_fade.restart();
    }

    // Sources resolve after the folder listing, so sync again once they do.
    onTrackChanged: Qt.callLater(audio.sync)
    onFilesChanged: Qt.callLater(audio.sync)

    FolderListModel {
        id: local_listing
        folder: Qt.resolvedUrl("audio")
        nameFilters: ["*.ogg", "*.wav"]
        showDirs: false
    }

    FolderListModel {
        id: data_listing
        folder: audio.local_has_files ? "" : audio.data_dir
        nameFilters: ["*.ogg", "*.wav"]
        showDirs: false
    }

    SequentialAnimation {
        id: title_fade
        NumberAnimation { target: audio; property: "title_level"; to: audio.track === "title" ? 1 : 0; duration: 800 }
        ScriptAction {
            script: {
                if (audio.track !== "title") {
                    title_intro.stop();
                    title_loop.stop();
                }
            }
        }
    }

    SequentialAnimation {
        id: fairy_fade
        NumberAnimation { target: audio; property: "fairy_level"; to: audio.track === "fairy" ? 1 : 0; duration: 800 }
        ScriptAction {
            script: {
                if (audio.track !== "fairy") {
                    fairy_intro.stop();
                    fairy_loop.stop();
                }
            }
        }
    }

    MediaPlayer {
        id: title_intro
        source: audio.file("title_intro.ogg")
        onSourceChanged: Qt.callLater(audio.sync)
        audioOutput: AudioOutput {
            volume: audio.title_level * audio.music_volume
        }
        onMediaStatusChanged: {
            if (title_intro.mediaStatus === MediaPlayer.EndOfMedia && audio.track === "title") title_loop.play();
        }
    }

    MediaPlayer {
        id: title_loop
        source: audio.file("title_loop.ogg")
        onSourceChanged: Qt.callLater(audio.sync)
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            volume: audio.title_level * audio.music_volume
        }
    }

    MediaPlayer {
        id: fairy_intro
        source: audio.file("fairy_intro.ogg")
        onSourceChanged: Qt.callLater(audio.sync)
        audioOutput: AudioOutput {
            volume: audio.fairy_level * audio.music_volume
        }
        onMediaStatusChanged: {
            if (fairy_intro.mediaStatus === MediaPlayer.EndOfMedia && audio.track === "fairy") fairy_loop.play();
        }
    }

    MediaPlayer {
        id: fairy_loop
        source: audio.file("fairy_loop.ogg")
        onSourceChanged: Qt.callLater(audio.sync)
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            volume: audio.fairy_level * audio.music_volume
        }
    }

    SoundEffect { id: fx_start; source: audio.file("start.wav"); volume: audio.fx_volume }
    SoundEffect { id: fx_move; source: audio.file("move.wav"); volume: audio.fx_volume }
    SoundEffect { id: fx_letter; source: audio.file("letter.wav"); volume: audio.fx_volume }
    SoundEffect { id: fx_decide; source: audio.file("decide.wav"); volume: audio.fx_volume }
    SoundEffect { id: fx_cancel; source: audio.file("cancel.wav"); volume: audio.fx_volume }
    SoundEffect { id: fx_error; source: audio.file("error.wav"); volume: audio.fx_volume }
}
