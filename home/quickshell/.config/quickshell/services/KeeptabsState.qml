// home/quickshell/.config/quickshell/services/KeeptabsState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// One keeptabs-waybar stream shared by every bar; it animates and idles on battery by itself.
Singleton {
    id: root

    property var runs: []
    property string state_class: "idle"
    property string tooltip: ""
    readonly property bool available: runs.length > 0
    readonly property string done_glyph: String.fromCodePoint(0xF1719)
    readonly property string wait_glyph: String.fromCodePoint(0xF169F)
    property int done_count: 0
    property int running_count: 0
    // False until the first line after (re)start, so a done state already present never celebrates.
    property bool primed: false
    property int last_seq: -1
    property int waiting_count: 0
    property int last_wait_seq: -1

    // A session went from running to done since the previous line.
    signal finished()
    // A session started waiting for input since the previous line.
    signal waiting_started()

    function count(state) {
        return root.tooltip.split("\n").filter(l => l.indexOf(state + "\t") === 0).length;
    }

    // Falls back to the waiting glyph group's badge when the tooltip has no WAITING lines.
    function waiting_in(runs) {
        const listed = root.count("WAITING");
        if (listed > 0) return listed;
        const i = runs.findIndex(r => r.text.indexOf(root.wait_glyph) !== -1);
        if (i === -1) return 0;
        const own = /(\d+)/.exec(runs[i].text.replace(root.wait_glyph, ""));
        const next = i + 1 < runs.length ? /^\s*(\d+)\s*$/.exec(runs[i + 1].text) : null;
        return own ? parseInt(own[1]) : next ? parseInt(next[1]) : 1;
    }

    // keeptabs' class is a string, or [class, "finished"] for 3s after a finish.
    function class_of(data) {
        return Array.isArray(data.class) ? data.class[0] : (data.class || "idle");
    }

    function decode(text) {
        return text.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&apos;|&#39;/g, "'").replace(/&amp;/g, "&");
    }

    // Flattens keeptabs' pango spans into runs of {text, color, rise}, dropping its zero-width struts.
    function parse(markup) {
        const out = [];
        const stack = [];
        const re = /<span([^>]*)>|<\/span>|([^<]+)/g;
        let m;
        while ((m = re.exec(markup)) !== null) {
            if (m[1] !== undefined) {
                const color = /color=["']([^"']+)["']/.exec(m[1]);
                const rise = /rise=["'](-?\d+)["']/.exec(m[1]);
                const top = stack.length ? stack[stack.length - 1] : { color: "", rise: 0 };
                stack.push({ color: color ? color[1] : top.color, rise: rise ? parseInt(rise[1]) : top.rise });
            } else if (m[0] === "</span>") {
                stack.pop();
            } else {
                const text = root.decode(m[2].replace(/\u200b/g, ""));
                if (!text) continue;
                const top = stack.length ? stack[stack.length - 1] : { color: "", rise: 0 };
                out.push({ text: text, color: top.color, rise: top.rise });
            }
        }
        // keeptabs pads the idle glyph with a trailing space for Waybar; drop edge whitespace.
        if (out.length) out[0].text = out[0].text.replace(/^\s+/, "");
        if (out.length) out[out.length - 1].text = out[out.length - 1].text.replace(/\s+$/, "");
        return out.filter(r => r.text !== "");
    }

    Process {
        id: stream
        command: ["sh", "-c", "exec ~/.local/bin/keeptabs-waybar"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    const runs = root.parse(data.text || "");
                    root.state_class = root.class_of(data);
                    root.tooltip = root.decode(data.tooltip || "");
                    const waiting = root.waiting_in(runs);
                    root.runs = runs;
                    let wait_rose;
                    if (typeof data.waiting_seq === "number") {
                        wait_rose = root.primed && data.waiting_seq > root.last_wait_seq;
                        root.last_wait_seq = data.waiting_seq;
                    } else {
                        wait_rose = root.primed && waiting > root.waiting_count;
                    }
                    root.waiting_count = waiting;
                    const done = root.count("DONE");
                    const was_running = root.running_count;
                    let rose;
                    if (typeof data.finished_seq === "number") {
                        rose = root.primed && data.finished_seq > root.last_seq;
                        root.last_seq = data.finished_seq;
                    } else {
                        rose = root.primed && done > root.done_count && was_running > 0;
                    }
                    root.done_count = done;
                    root.running_count = root.count("RUNNING");
                    root.primed = true;
                    if (rose) root.finished();
                    if (wait_rose) root.waiting_started();
                } catch (e) {
                    console.warn("keeptabs: " + e);
                }
            }
        }
        onExited: {
            root.primed = false;
            restart_timer.start();
        }
    }

    Timer {
        id: restart_timer
        interval: 5000
        onTriggered: stream.running = true
    }
}
