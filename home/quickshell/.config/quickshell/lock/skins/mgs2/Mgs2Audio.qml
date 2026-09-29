// home/quickshell/.config/quickshell/lock/skins/mgs2/Mgs2Audio.qml
import QtQuick
import QtMultimedia
import Qt.labs.folderlistmodel
import Quickshell

// The MGS2 skin's music and sound effects (made by scripts/mgs2-audio): the skin's own audio/ when it holds
// files (the greeter's staged copy), else the user's data dir; a missing file stays silent.
Item {
    id: audio

    // "title", "menu" or "".
    property string track: ""
    readonly property real music_volume: 0.4
    readonly property real fx_volume: 0.4
    property real title_level: 0
    property real menu_level: 0
    readonly property string data_dir: "file://" + (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/quickshell/mgs2-audio"
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
        const fx = ({ back: fx_back, select: fx_select, error: fx_error, submit: fx_submit, transition_wipe: fx_wipe, transition_left: fx_left, transition_right: fx_right })[name];
        if (fx && fx.status === SoundEffect.Ready) fx.play();
    }

    // Without a menu theme of its own, the menus keep the title theme playing.
    readonly property string playing: audio.track === "menu" && !audio.files["menu_loop.ogg"] && !audio.files["menu_intro.ogg"] ? "title" : audio.track

    function sync() {
        const title_on = title_intro.playbackState === MediaPlayer.PlayingState || title_loop.playbackState === MediaPlayer.PlayingState;
        if (audio.playing === "title" && !title_on) {
            if (audio.files["title_intro.ogg"]) title_intro.play();
            else title_loop.play();
        }
        const menu_on = menu_intro.playbackState === MediaPlayer.PlayingState || menu_loop.playbackState === MediaPlayer.PlayingState;
        if (audio.playing === "menu" && !menu_on) {
            if (audio.files["menu_intro.ogg"]) menu_intro.play();
            else menu_loop.play();
        }
        title_fade.restart();
        menu_fade.restart();
    }

    // Sources resolve after the folder listing, so sync again once they do.
    onPlayingChanged: Qt.callLater(audio.sync)
    onFilesChanged: Qt.callLater(audio.sync)

    MediaDevices {
        id: devices
        property bool had_output: false
        Component.onCompleted: devices.had_output = devices.defaultAudioOutput.mode !== AudioDevice.Null
        // Players started with no sink stay silent, so restart them once one appears.
        onDefaultAudioOutputChanged: {
            if (!devices.had_output) {
                title_intro.stop();
                title_loop.stop();
                menu_intro.stop();
                menu_loop.stop();
                Qt.callLater(audio.sync);
            }
            devices.had_output = devices.defaultAudioOutput.mode !== AudioDevice.Null;
        }
    }

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
        NumberAnimation { target: audio; property: "title_level"; to: audio.playing === "title" ? 1 : 0; duration: 800 }
        ScriptAction {
            script: {
                if (audio.playing !== "title") {
                    title_intro.stop();
                    title_loop.stop();
                }
            }
        }
    }

    SequentialAnimation {
        id: menu_fade
        NumberAnimation { target: audio; property: "menu_level"; to: audio.playing === "menu" ? 1 : 0; duration: 800 }
        ScriptAction {
            script: {
                if (audio.playing !== "menu") {
                    menu_intro.stop();
                    menu_loop.stop();
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
            if (title_intro.mediaStatus === MediaPlayer.EndOfMedia && audio.playing === "title") title_loop.play();
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

    MediaPlayer {
        id: menu_intro
        source: audio.file("menu_intro.ogg")
        onSourceChanged: Qt.callLater(audio.sync)
        audioOutput: AudioOutput {
            device: devices.defaultAudioOutput
            volume: audio.menu_level * audio.music_volume
        }
        onMediaStatusChanged: {
            if (menu_intro.mediaStatus === MediaPlayer.EndOfMedia && audio.playing === "menu") menu_loop.play();
        }
    }

    MediaPlayer {
        id: menu_loop
        source: audio.file("menu_loop.ogg")
        onSourceChanged: Qt.callLater(audio.sync)
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            device: devices.defaultAudioOutput
            volume: audio.menu_level * audio.music_volume
        }
    }

    SoundEffect { id: fx_back; source: audio.file("back.wav"); audioDevice: devices.defaultAudioOutput; volume: audio.fx_volume }
    SoundEffect { id: fx_select; source: audio.file("select.wav"); audioDevice: devices.defaultAudioOutput; volume: audio.fx_volume }
    SoundEffect { id: fx_error; source: audio.file("error.wav"); audioDevice: devices.defaultAudioOutput; volume: audio.fx_volume }
    SoundEffect { id: fx_submit; source: audio.file("submit.wav"); audioDevice: devices.defaultAudioOutput; volume: audio.fx_volume }
    SoundEffect { id: fx_wipe; source: audio.file("transition_wipe.wav"); audioDevice: devices.defaultAudioOutput; volume: audio.fx_volume }
    SoundEffect { id: fx_left; source: audio.file("transition_left.wav"); audioDevice: devices.defaultAudioOutput; volume: audio.fx_volume }
    SoundEffect { id: fx_right; source: audio.file("transition_right.wav"); audioDevice: devices.defaultAudioOutput; volume: audio.fx_volume }
}
