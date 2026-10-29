import QtQuick
import Quickshell
import Quickshell.Io
import qs.features.lock

// Lets the voice key answer the open picker, whoever opened it: while a voice_answerable provider waits for an answer,
// its question is published as voxcmd's pending pick, and PickerIpc's answer, expand and cancel come back here. The
// file and the calls are the contract in the voxcmd README ("Pickers the bar publishes").
Scope {
    id: root

    readonly property var provider: Pickers.is_open && Pickers.provider && Pickers.provider.voice_answerable ? Pickers.provider : null
    readonly property var question: root.provider ? root.provider.voice_question : null
    // New on every open, so an answer read from an earlier picker (closed, reopened, or shown before a reload, which
    // keeps the pid) is refused as stale.
    property string token: ""

    readonly property string pid: String(Quickshell.processId)
    readonly property string voxcmd_dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/voxcmd"
    // The file text the open question wants, "" for none.
    readonly property string wanted_text: root.question ? JSON.stringify(Object.assign({ pid: Quickshell.processId, owner: "bar", token: root.token }, root.question)) : ""
    // What the writer last made of `wanted_text`, and the start of a file it may have left that is still this bar's to
    // remove. The start-up value removes one an earlier load of this process left (a reload keeps the pid).
    property string synced_text: "\u0000"
    property string own_file_start: "{\"pid\":" + root.pid + ",\"owner\":\"bar\","

    onQuestionChanged: {
        if (!root.question) root.token = "";
        else if (root.token === "") root.token = Date.now().toString(36) + Math.floor(Math.random() * 1e9).toString(36);
    }
    onWanted_textChanged: Qt.callLater(root.sync)
    Component.onCompleted: root.sync()
    Component.onDestruction: {
        if (root.own_file_start !== "") Quickshell.execDetached(["sh", "-c", root.sync_script, "sh", root.voxcmd_dir, "", root.own_file_start]);
    }

    // The answers PickerIpc takes. Each returns "ok", "locked" while the screen is locked, or "stale" when `token` is
    // not the open picker's or what it names is not shown any more.
    function answer(token, text) {
        const refused = root.refusal(token, false);
        if (refused !== "") return refused;
        return root.provider.voice_answer(text) ? "ok" : "stale";
    }

    // An empty token expands whatever voice-answerable picker is open: a voxcmd ask's picker is shown here but not
    // published, so voxcmd has no token for it. Returns "unknown" when the item has no list under it.
    function expand(index, token) {
        const refused = root.refusal(token, true);
        if (refused !== "") return refused;
        return root.provider.voice_expand(index) ? "ok" : "unknown";
    }

    function cancel(token) {
        const refused = root.refusal(token, false);
        if (refused !== "") return refused;
        Pickers.close();
        return "ok";
    }

    function refusal(token, any_token) {
        if (Lock.locked) return "locked";
        if (!root.question) return "stale";
        if (token !== root.token && !(any_token && token === "")) return "stale";
        return "";
    }

    function sync() {
        if (writer.running || root.wanted_text === root.synced_text) return;
        writer.syncing_text = root.wanted_text;
        writer.command = ["sh", "-c", root.sync_script, "sh", root.voxcmd_dir, root.wanted_text, root.own_file_start];
        writer.running = true;
    }

    // sh -c <script> sh <dir> <text> <mine>: with text, writes it as the pending pick in one step, unless a live voxcmd
    // ask owns the file (exit 3): the ask answers through its own FIFO and keeps its listen bookkeeping there, and
    // shows its picker through this bar anyway. With no text, removes the file only while it starts with <mine>.
    // `voxcmd util pending-pick` prints the file only while its writer is live; a missing voxcmd reads as nobody.
    readonly property string sync_script: `dir=$1 text=$2 mine=$3 file=$1/pending-pick.json
if [ -z "$text" ]; then
  [ -z "$mine" ] && exit 0
  case $(cat "$file" 2>/dev/null) in "$mine"*) rm -f "$file" ;; esac
  exit 0
fi
if live=$(voxcmd util pending-pick 2>/dev/null); then
  case $live in "{\\"pid\\":"*",\\"owner\\":\\"bar\\","*) ;; *) exit 3 ;; esac
fi
mkdir -p "$dir" && printf "%s\\n" "$text" >"$file.$$" && mv -f "$file.$$" "$file"`

    Process {
        id: writer
        property string syncing_text: ""
        onExited: code => {
            root.synced_text = writer.syncing_text;
            // A bar file is this bar's to remove by its token only once written; skipped or removed, nothing is.
            root.own_file_start = code === 0 && writer.syncing_text !== "" ? "{\"pid\":" + root.pid + ",\"owner\":\"bar\",\"token\":\"" + JSON.parse(writer.syncing_text).token + "\"," : "";
            root.sync();
        }
    }
}
