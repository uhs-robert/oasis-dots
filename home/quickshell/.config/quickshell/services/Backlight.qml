// home/quickshell/.config/quickshell/services/Backlight.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string device_dir: ""
    readonly property bool has_device: device_dir !== ""
    property int brightness: 0
    property int max_brightness: 1
    readonly property int percent: max_brightness > 0 ? Math.round(brightness / max_brightness * 100) : 0

    property string kbd_device_dir: ""
    readonly property bool has_kbd: kbd_device_dir !== ""
    property int kbd_brightness: 0
    property int kbd_max_brightness: 1
    readonly property int kbd_percent: kbd_max_brightness > 0 ? Math.round(kbd_brightness / kbd_max_brightness * 100) : 0

    function refresh() {
        if (root.has_device) {
            brightness_file.reload();
            max_brightness_file.reload();
        }
        if (root.has_kbd) {
            kbd_brightness_file.reload();
            kbd_max_brightness_file.reload();
        }
    }

    // Slider drags fire faster than brightnessctl exits; absolute sets coalesce to the latest.
    property var pending: []

    function enqueue(cmd, key) {
        if (key) pending = pending.filter(p => p.key !== key);
        pending.push({ cmd: cmd, key: key });
        drain();
    }

    function drain() {
        if (write_proc.running || pending.length === 0) return;
        write_proc.command = pending.shift().cmd;
        write_proc.running = true;
    }

    // brightnessctl clamps at 1% floor so a scroll or key never blacks out the screen.
    function bump(delta) {
        const cmd = delta > 0 ? ["brightnessctl", "set", "5%+"] : ["brightnessctl", "-n1", "set", "5%-"];
        root.enqueue(cmd, "");
    }

    function set_percent(pct) {
        const clamped = Math.max(1, Math.min(100, Math.round(pct)));
        root.enqueue(["brightnessctl", "set", clamped + "%"], "screen");
    }

    function kbd_bump(delta) {
        const dev = root.kbd_device_dir.split("/").pop();
        const cmd = delta > 0 ? ["brightnessctl", "-d", dev, "set", "5%+"] : ["brightnessctl", "-d", dev, "-n0", "set", "5%-"];
        root.enqueue(cmd, "");
    }

    function kbd_set_percent(pct) {
        const dev = root.kbd_device_dir.split("/").pop();
        const clamped = Math.max(0, Math.min(100, Math.round(pct)));
        root.enqueue(["brightnessctl", "-d", dev, "set", clamped + "%"], "kbd");
    }

    Process {
        id: find_proc
        command: ["sh", "-c", "ls /sys/class/backlight 2>/dev/null | head -1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                if (name) root.device_dir = "/sys/class/backlight/" + name;
            }
        }
    }

    Process {
        id: find_kbd_proc
        command: ["sh", "-c", "ls -d /sys/class/leds/*kbd_backlight* 2>/dev/null | head -1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path) root.kbd_device_dir = path;
            }
        }
    }

    onDevice_dirChanged: if (root.has_device) {
        brightness_file.reload();
        max_brightness_file.reload();
    }

    onKbd_device_dirChanged: if (root.has_kbd) {
        kbd_brightness_file.reload();
        kbd_max_brightness_file.reload();
    }

    Process {
        id: write_proc
        onExited: {
            root.refresh();
            root.drain();
        }
    }

    FileView {
        id: brightness_file
        path: root.has_device ? root.device_dir + "/brightness" : ""
        onLoaded: root.brightness = parseInt(text()) || 0
    }

    FileView {
        id: max_brightness_file
        path: root.has_device ? root.device_dir + "/max_brightness" : ""
        onLoaded: root.max_brightness = parseInt(text()) || 1
    }

    FileView {
        id: kbd_brightness_file
        path: root.has_kbd ? root.kbd_device_dir + "/brightness" : ""
        onLoaded: root.kbd_brightness = parseInt(text()) || 0
    }

    FileView {
        id: kbd_max_brightness_file
        path: root.has_kbd ? root.kbd_device_dir + "/max_brightness" : ""
        onLoaded: root.kbd_max_brightness = parseInt(text()) || 1
    }
}
