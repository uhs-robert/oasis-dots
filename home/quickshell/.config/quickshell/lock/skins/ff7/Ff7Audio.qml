// home/quickshell/.config/quickshell/lock/skins/ff7/Ff7Audio.qml
import QtQuick
import QtMultimedia
import Qt.labs.folderlistmodel

// The FF7 skin's music and sound effects from audio/ (made by scripts/ff7-audio); a missing file stays silent.
Item {
    id: audio

    // "title" or "".
    property string track: ""
    readonly property real music_volume: 0.4
    readonly property real fx_volume: 0.4
    property real title_level: 0
    readonly property var files: {
        const out = {};
        for (let i = 0; i < listing.count; i++) out[listing.get(i, "fileName")] = true;
        return out;
    }

    function file(name) {
        return audio.files[name] ? Qt.resolvedUrl("audio/" + name) : "";
    }

    function play(name) {
        const fx = ({ cursor: fx_cursor, select: fx_cursor, cancel: fx_cancel, buzzer: fx_buzzer, loading: fx_loading, loaded: fx_loaded })[name];
        if (fx && fx.status === SoundEffect.Ready) fx.play();
    }

    function sync() {
        const title_on = title_intro.playbackState === MediaPlayer.PlayingState || title_loop.playbackState === MediaPlayer.PlayingState;
        if (audio.track === "title" && !title_on) {
            if (audio.files["title_intro.ogg"]) title_intro.play();
            else title_loop.play();
        }
        title_fade.restart();
    }

    onTrackChanged: Qt.callLater(audio.sync)
    onFilesChanged: Qt.callLater(audio.sync)

    MediaDevices {
        id: devices
        property bool had_output: false
        Component.onCompleted: devices.had_output = !devices.defaultAudioOutput.isNull
        // Players started with no sink stay silent, so restart them once one appears.
        onDefaultAudioOutputChanged: {
            if (!devices.had_output) {
                title_intro.stop();
                title_loop.stop();
                Qt.callLater(audio.sync);
            }
            devices.had_output = !devices.defaultAudioOutput.isNull;
        }
    }

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

    MediaPlayer {
        id: title_intro
        source: audio.file("title_intro.ogg")
        onSourceChanged: Qt.callLater(audio.sync)
        audioOutput: AudioOutput {
            device: devices.defaultAudioOutput
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
            device: devices.defaultAudioOutput
            volume: audio.title_level * audio.music_volume
        }
    }

    SoundEffect { id: fx_cursor; source: audio.file("cursor.wav"); audioDevice: devices.defaultAudioOutput; volume: audio.fx_volume }
    SoundEffect { id: fx_cancel; source: audio.file("cancel.wav"); audioDevice: devices.defaultAudioOutput; volume: audio.fx_volume }
    SoundEffect { id: fx_buzzer; source: audio.file("buzzer.wav"); audioDevice: devices.defaultAudioOutput; volume: audio.fx_volume }
    SoundEffect { id: fx_loading; source: audio.file("loading.wav"); audioDevice: devices.defaultAudioOutput; volume: audio.fx_volume }
    SoundEffect { id: fx_loaded; source: audio.file("loaded.wav"); audioDevice: devices.defaultAudioOutput; volume: audio.fx_volume }
}
