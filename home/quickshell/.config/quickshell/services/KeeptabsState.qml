// home/quickshell/.config/quickshell/services/KeeptabsState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One keeptabs-waybar stream shared by every bar; it animates and idles on battery by itself.
Singleton {
    id: root

    property var runs: []
    property string state_class: "idle"
    property string tooltip: ""
    readonly property bool available: runs.length > 0
    readonly property string done_glyph: String.fromCodePoint(0xF1719)
    property int done_count: 0
    property int running_count: 0
    // False until the first line after (re)start, so a done state already present never celebrates.
    property bool primed: false

    // A session went from running to done since the previous line.
    signal finished()

    function count(state) {
        return root.tooltip.split("\n").filter(l => l.indexOf(state + "\t") === 0).length;
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
                    root.runs = root.parse(data.text || "");
                    root.state_class = data.class || "idle";
                    root.tooltip = root.decode(data.tooltip || "");
                    const done = root.count("DONE");
                    const was_running = root.running_count;
                    const rose = root.primed && done > root.done_count && was_running > 0;
                    root.done_count = done;
                    root.running_count = root.count("RUNNING");
                    root.primed = true;
                    if (rose) root.finished();
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
