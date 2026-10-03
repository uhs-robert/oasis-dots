// home/quickshell/.config/quickshell/lock/skins/ff7/Ff7Audio.qml
import QtQuick
import Qt.labs.folderlistmodel
import "../sound"

// The FF7 skin's music and sound effects from audio/ (made by scripts/ff7-audio); a missing file stays silent.
Item {
    id: audio

    // "title" or "".
    property string track: ""
    property real music_setting: 0.5
    readonly property real music_volume: audio.music_setting * 0.8
    readonly property real fx_volume: 0.4
    property real title_level: 0
    property bool fx_used: false
    readonly property var files: {
        const out = {};
        for (let i = 0; i < listing.count; i++) out[listing.get(i, "fileName")] = true;
        return out;
    }
    readonly property var fx_files: ({ cursor: "cursor.wav", select: "cursor.wav", cancel: "cancel.wav", buzzer: "buzzer.wav", loading: "loading.wav", loaded: "loaded.wav" })

    function file(name) {
        return audio.files[name] ? Qt.resolvedUrl("audio/" + name).toString() : "";
    }

    function play(name) {
        const url = audio.file(audio.fx_files[name] || "");
        if (url === "") return;
        fx.queue(["loadfile", url, "replace"]);
        audio.fx_used = true;
    }

    // `to` is set here, not bound: a binding on track may not have updated yet when this handler runs.
    onTrackChanged: {
        title_fade.to = audio.track === "title" ? 1 : 0;
        title_fade.restart();
    }

    FolderListModel {
        id: listing
        folder: Qt.resolvedUrl("audio")
        nameFilters: ["*.ogg", "*.wav"]
        showDirs: false
    }

    NumberAnimation {
        id: title_fade
        target: audio
        property: "title_level"
        duration: 800
    }

    MpvProcess {
        readonly property string loop: audio.file("title_loop.ogg")
        wanted: loop !== "" && (audio.track === "title" || audio.title_level > 0)
        args: (audio.file("title_intro.ogg") !== "" ? [audio.file("title_intro.ogg")] : []).concat(["--{", "--loop-file=inf", loop, "--}"])
        volume: audio.title_level * audio.music_volume
    }

    MpvProcess {
        id: fx
        wanted: audio.fx_used
        args: ["--idle=yes"]
        volume: audio.fx_volume
    }
}
