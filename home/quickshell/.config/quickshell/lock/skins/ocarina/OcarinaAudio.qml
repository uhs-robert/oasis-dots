// home/quickshell/.config/quickshell/lock/skins/ocarina/OcarinaAudio.qml
import QtQuick
import QtMultimedia
import Qt.labs.folderlistmodel

// The Ocarina skin's music and sound effects from audio/ (made by scripts/ocarina-audio); a missing file stays silent.
Item {
    id: audio

    // "title", "fairy" or "".
    property string track: ""
    readonly property real music_volume: 0.4
    readonly property real fx_volume: 0.4
    property real title_level: 0
    property real fairy_level: 0
    readonly property var files: {
        const out = {};
        for (let i = 0; i < listing.count; i++) out[listing.get(i, "fileName")] = true;
        return out;
    }

    function file(name) {
        return audio.files[name] ? Qt.resolvedUrl("audio/" + name) : "";
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
        if (audio.track === "fairy" && fairy.playbackState !== MediaPlayer.PlayingState) fairy.play();
        title_fade.restart();
        fairy_fade.restart();
    }

    // Sources resolve after the folder listing, so sync again once they do.
    onTrackChanged: Qt.callLater(audio.sync)
    onFilesChanged: Qt.callLater(audio.sync)

    FolderListModel {
        id: listing
        folder: Qt.resolvedUrl("audio")
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
                if (audio.track !== "fairy") fairy.stop();
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
        id: fairy
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
