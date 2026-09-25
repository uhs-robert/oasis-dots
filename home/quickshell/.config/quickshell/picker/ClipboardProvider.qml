// home/quickshell/.config/quickshell/picker/ClipboardProvider.qml
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// cliphist history, newest first: Enter copies an entry back, `d` deletes it in place.
PickerProvider {
    id: root

    name: "clipboard"
    title: "Clipboard"
    placeholder: "Search clipboard"
    verb: "copy"
    rank_by_usage: false
    keep_order: true
    actions: [{ key: "d", desc: "delete" }]

    readonly property string cache_dir: (Quickshell.env("XDG_RUNTIME_DIR") || Quickshell.cacheDir) + "/quickshell-cliphist"
    readonly property string text_icon: Quickshell.iconPath("text-x-generic", "edit-paste")
    readonly property string image_icon: Quickshell.iconPath("image-x-generic", "edit-paste")
    readonly property var image_exts: ["png", "jpeg", "jpg", "gif", "bmp", "webp"]

    // id -> decoded text / image file url, filled lazily for the selected entry only.
    property var texts: ({})
    property var images: ({})
    property var pending: null
    property var delete_queue: []
    // id -> -1 while its delete runs, then the first list seq that is sure to omit it.
    property var deleting: ({})
    property int list_seq: 0
    property int ready_seq: 0
    property bool relist: false
    property int items_seq: 0
    // Actions wait for a list started after this open, so a fast `d` never hits a stale row.
    readonly property bool ready: root.ready_seq > 0 && root.items_seq >= root.ready_seq

    function parse(text) {
        const out = [];
        for (const line of text.split("\n")) {
            const tab = line.indexOf("\t");
            if (tab <= 0) continue;
            const id = line.slice(0, tab);
            if (root.deleting[id] !== undefined) continue;
            const shown = line.slice(tab + 1);
            const bin = /^\[\[ binary data (\S+ \S+)(?: (\S+))?(?: (\d+)x(\d+))? \]\]$/.exec(shown);
            const ext = bin && bin[2] ? bin[2].toLowerCase() : "";
            const is_image = !!bin && root.image_exts.indexOf(ext) >= 0;
            out.push({
                id: id,
                line: line,
                kind: is_image ? "image" : bin ? "binary" : "text",
                ext: ext,
                label: is_image ? "Image " + (bin[3] ? bin[3] + "x" + bin[4] : ext) : bin ? "Binary data" : shown,
                description: bin ? [ext.toUpperCase(), bin[3] ? bin[3] + "x" + bin[4] : "", bin[1]].filter(s => s !== "").join(" · ") : "",
                icon_path: is_image ? root.image_icon : root.text_icon,
                keywords: bin ? ["image", ext] : []
            });
        }
        return out;
    }

    function keep_only(map, ids) {
        const next = {};
        for (const k in map) if (ids[k]) next[k] = map[k];
        return next;
    }

    function listed(text, seq) {
        const d = {};
        for (const id in root.deleting) if (root.deleting[id] < 0 || root.deleting[id] > seq) d[id] = root.deleting[id];
        root.deleting = d;
        const next = root.parse(text);
        const ids = {};
        for (const e of next) ids[e.id] = true;
        root.texts = root.keep_only(root.texts, ids);
        root.images = root.keep_only(root.images, ids);
        root.items_seq = seq;
        root.items = next;
        const keep = next.filter(e => e.kind === "image").map(e => e.id);
        Quickshell.execDetached(["sh", "-c", "cd \"$1\" 2>/dev/null || exit 0; shift; keep=\" $* \"; for f in *; do [ -f \"$f\" ] || continue; case \"$keep\" in *\" ${f%%.*} \"*) ;; *) rm -f -- \"$f\" ;; esac; done", "sh", root.cache_dir].concat(keep));
    }

    // A list already running may predate a change, so it runs once more after it lands.
    function start_list() {
        if (list_proc.running) {
            root.relist = true;
            return;
        }
        root.list_seq++;
        list_proc.seq = root.list_seq;
        list_proc.running = true;
    }

    // Mode "delete" opens in NORMAL, ready for `d`.
    function refresh(arg) {
        root.starts_insert = arg !== "delete";
        root.ready_seq = root.list_seq + 1;
        root.start_list();
    }

    // Output starts with "<kind> <id>", so a late result can never land on the wrong entry.
    function request(entry) {
        if (!entry || !entry.id || entry.kind === "binary") return;
        if (entry.kind === "text" && root.texts[entry.id] !== undefined) return;
        if (entry.kind === "image" && root.images[entry.id] !== undefined) return;
        if (decode_proc.running) {
            root.pending = entry;
            return;
        }
        decode_proc.command = entry.kind === "image"
            ? ["sh", "-c", "f=\"$1/$2.$3\"; mkdir -p \"$1\" && { [ -s \"$f\" ] || { cliphist decode \"$2\" > \"$f.tmp\" && mv \"$f.tmp\" \"$f\"; }; } && printf 'image %s\\n%s' \"$2\" \"$f\"", "sh", root.cache_dir, entry.id, entry.ext]
            : ["sh", "-c", "printf 'text %s\\n' \"$1\"; cliphist decode \"$1\" | head -c 6000", "sh", entry.id];
        decode_proc.running = true;
    }

    function decoded(out) {
        const nl = out.indexOf("\n");
        const head = /^(image|text) (\d+)$/.exec(nl > 0 ? out.slice(0, nl) : "");
        if (!head) return;
        const is_image = head[1] === "image";
        const id = head[2];
        const next = Object.assign({}, is_image ? root.images : root.texts);
        next[id] = is_image ? "file://" + out.slice(nl + 1) : out.slice(nl + 1);
        if (is_image) root.images = next; else root.texts = next;
    }

    function activate(item) {
        if (!root.ready) return;
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist decode | wl-copy", "sh", item.line]);
    }

    // The row goes at once; the history is re-read after the last queued delete lands.
    function run_action(key, item) {
        if (key !== "d" || !root.ready || root.deleting[item.id] !== undefined) return;
        const d = Object.assign({}, root.deleting);
        d[item.id] = -1;
        root.deleting = d;
        root.items = root.items.filter(e => e.id !== item.id);
        root.delete_queue = root.delete_queue.concat([item]);
        root.flush_deletes();
    }

    function flush_deletes() {
        if (delete_proc.running || root.delete_queue.length === 0) return;
        const batch = root.delete_queue;
        root.delete_queue = [];
        delete_proc.batch = batch.map(e => e.id);
        delete_proc.command = ["sh", "-c", "printf '%s\\n' \"$@\" | cliphist delete", "sh"].concat(batch.map(e => e.line));
        delete_proc.running = true;
    }

    Process {
        id: list_proc
        property int seq: 0
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.listed(text, list_proc.seq)
        }
        onExited: if (root.relist) {
            root.relist = false;
            Qt.callLater(root.start_list);
        }
    }

    Process {
        id: decode_proc
        stdout: StdioCollector {
            onStreamFinished: root.decoded(text)
        }
        onExited: {
            const next = root.pending;
            root.pending = null;
            if (next) Qt.callLater(root.request, next);
        }
    }

    Process {
        id: delete_proc
        property var batch: []
        onExited: {
            const d = Object.assign({}, root.deleting);
            const after = root.list_seq + 1;
            for (const id of delete_proc.batch) d[id] = after;
            root.deleting = d;
            if (root.delete_queue.length > 0) Qt.callLater(root.flush_deletes);
            else root.start_list();
        }
    }

    preview: Component {
        Item {
            id: pane
            property var entry: null
            readonly property string text_value: pane.entry && pane.entry.kind === "text" ? (root.texts[pane.entry.id] !== undefined ? root.texts[pane.entry.id] : pane.entry.label) : ""
            readonly property string image_source: pane.entry && pane.entry.kind === "image" ? root.images[pane.entry.id] || "" : ""

            onEntryChanged: root.request(pane.entry)
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: Style.radius(4)
                color: Theme.bg_surface
            }

            Text {
                anchors.fill: parent
                anchors.margins: 10
                visible: !!pane.entry && pane.entry.kind !== "image"
                text: pane.entry ? (pane.entry.kind === "text" ? pane.text_value : pane.entry.description) : ""
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideRight
                color: pane.entry && pane.entry.kind === "text" && root.texts[pane.entry.id] !== undefined ? Style.text_fg : Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }

            Image {
                anchors.fill: parent
                anchors.margins: 6
                visible: pane.image_source !== ""
                source: pane.image_source
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
        }
    }
}
