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
        return out;
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
                } catch (e) {
                    console.warn("keeptabs: " + e);
                }
            }
        }
        onExited: restart_timer.start()
    }

    Timer {
        id: restart_timer
        interval: 5000
        onTriggered: stream.running = true
    }
}
