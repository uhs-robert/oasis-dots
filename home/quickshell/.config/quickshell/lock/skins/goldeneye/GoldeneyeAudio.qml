// home/quickshell/.config/quickshell/lock/skins/goldeneye/GoldeneyeAudio.qml
import QtQuick
import QtMultimedia
import Qt.labs.folderlistmodel
import Quickshell

// The GoldenEye skin's music and effects. Files in the skin's own audio/ (the greeter's staged copy) else the data dir win over the shipped fx/;
// the music (music.ogg, .wav or .mp3) is not shipped, and a missing file stays silent.
Item {
    id: audio

    property bool playing: false
    property real music_setting: 0.5
    readonly property real music_volume: audio.music_setting * 0.8
    readonly property real fx_volume: 0.4
    property real music_level: 0
    readonly property string data_dir: "file://" + (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/quickshell/goldeneye-audio"
    readonly property bool local_has_files: local_listing.count > 0
    readonly property string base: audio.local_has_files ? Qt.resolvedUrl("audio") : audio.data_dir
    readonly property var files: {
        const out = {};
        const listing = audio.local_has_files ? local_listing : data_listing;
        for (let i = 0; i < listing.count; i++) out[listing.get(i, "fileName")] = true;
        return out;
    }
    readonly property var shipped: ["lock_close.wav", "lock_open.wav", "static.wav", "select.wav", "confirm.wav", "back.wav", "type.wav", "error.wav"]
    readonly property string music_file: ["music.ogg", "music.wav", "music.mp3"].find(n => audio.files[n]) || ""
    property string pending: ""

    function file(name) {
        if (audio.files[name]) return audio.base + "/" + name;
        return audio.shipped.indexOf(name) >= 0 ? Qt.resolvedUrl("fx/" + name) : "";
    }

    function play(name) {
        const fx = ({ lock_close: fx_lock_close, lock_open: fx_lock_open, static: fx_static, select: fx_select, confirm: fx_confirm, back: fx_back, type: fx_type, error: fx_error })[name];
        if (!fx || String(fx.source) === "") return;
        if (fx.status === SoundEffect.Ready) fx.play();
        else audio.pending = name;
    }

    function sync() {
        if (audio.playing && audio.music_file !== "" && music.playbackState !== MediaPlayer.PlayingState) music.play();
        music_fade.to = audio.playing ? 1 : 0;
        music_fade.restart();
    }

    onPlayingChanged: Qt.callLater(audio.sync)
    onMusic_fileChanged: Qt.callLater(audio.sync)

    MediaDevices {
        id: devices
        property bool had_output: false
        Component.onCompleted: devices.had_output = devices.defaultAudioOutput.mode !== AudioDevice.Null
        // A player started with no sink stays silent, so restart it once one appears.
        onDefaultAudioOutputChanged: {
            if (!devices.had_output) {
                music.stop();
                Qt.callLater(audio.sync);
            }
            devices.had_output = devices.defaultAudioOutput.mode !== AudioDevice.Null;
        }
    }

    FolderListModel {
        id: local_listing
        folder: Qt.resolvedUrl("audio")
        nameFilters: ["*.ogg", "*.wav", "*.mp3"]
        showDirs: false
    }

    FolderListModel {
        id: data_listing
        folder: audio.local_has_files ? "" : audio.data_dir
        nameFilters: ["*.ogg", "*.wav", "*.mp3"]
        showDirs: false
    }

    SequentialAnimation {
        id: music_fade
        property real to: 0
        NumberAnimation { target: audio; property: "music_level"; to: music_fade.to; duration: 800 }
        ScriptAction { script: if (!audio.playing) music.stop() }
    }

    MediaPlayer {
        id: music
        source: audio.music_file !== "" ? audio.base + "/" + audio.music_file : ""
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            device: devices.defaultAudioOutput
            volume: audio.music_level * audio.music_volume
        }
    }

    component Fx: SoundEffect {
        id: fx
        required property string name
        source: audio.file(fx.name + ".wav")
        audioDevice: devices.defaultAudioOutput
        volume: audio.fx_volume
        onStatusChanged: {
            if (fx.status === SoundEffect.Ready && audio.pending === fx.name) {
                audio.pending = "";
                fx.play();
            }
        }
    }

    Fx { id: fx_lock_close; name: "lock_close" }
    Fx { id: fx_lock_open; name: "lock_open" }
    Fx { id: fx_static; name: "static" }
    Fx { id: fx_select; name: "select" }
    Fx { id: fx_confirm; name: "confirm" }
    Fx { id: fx_back; name: "back" }
    Fx { id: fx_type; name: "type" }
    Fx { id: fx_error; name: "error" }
}
