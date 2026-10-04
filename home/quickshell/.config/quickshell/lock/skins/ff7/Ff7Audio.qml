// home/quickshell/.config/quickshell/lock/skins/ff7/Ff7Audio.qml
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import "../sound"

// The FF7 skin's music and sound effects (made by scripts/ff7-audio): the skin's own audio/ when it holds
// files (the greeter's staged copy, or an older in-tree import), else the user's data dir; a missing file stays silent.
Item {
    id: audio

    // "title" or "".
    property string track: ""
    property real music_setting: 0.5
    readonly property real music_volume: audio.music_setting * 0.8
    readonly property real fx_volume: 0.4
    property real title_level: 0
    property bool fx_used: false
    readonly property string data_dir: "file://" + (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/quickshell/ff7-audio"
    readonly property bool local_has_files: local_listing.count > 0
    readonly property string base: audio.local_has_files ? Qt.resolvedUrl("audio") : audio.data_dir
    readonly property var files: {
        const out = {};
        const listing = audio.local_has_files ? local_listing : data_listing;
        for (let i = 0; i < listing.count; i++) out[listing.get(i, "fileName")] = true;
        return out;
    }
    readonly property var fx_files: ({ cursor: "cursor.wav", select: "cursor.wav", cancel: "cancel.wav", buzzer: "buzzer.wav", loading: "loading.wav", loaded: "loaded.wav" })

    function file(name) {
        return audio.files[name] ? audio.base + "/" + name : "";
    }

    function play(name) {
        const url = audio.file(audio.fx_files[name] || "");
        if (url === "") return;
        fx.queue(["loadfile", url, "replace"]);
        audio.fx_used = true;
    }

    // `to` is set here, not bound: a binding on track may not have updated yet when this handler runs.
    onTrackChanged: {
        if (audio.track !== "") audio.fx_used = true;
        title_fade.to = audio.track === "title" ? 1 : 0;
        title_fade.restart();
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
