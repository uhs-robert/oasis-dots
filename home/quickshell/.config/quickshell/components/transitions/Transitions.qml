pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../services"
import "Kinds.js" as Kinds

// Owns the displayed style: a change covers the old look, swaps Style.name while covered, then reveals the new one.
Singleton {
    id: root

    signal play(string kind, int start_at)
    signal stop()

    property bool armed: false
    // The style the bars should end up showing.
    property string target: ""
    // idle, cover (old look going out) or reveal (new look coming in).
    property string phase: "idle"
    // A fresh process holds every bar covered until the intro reveals the saved style.
    property bool intro: false

    function valid(name) {
        return Style.names.indexOf(name) >= 0;
    }

    // Shows `name` on the bars; `now` skips the 250ms rest a scrolling preview waits for.
    function show(name, now) {
        if (!root.valid(name)) return;
        root.target = name;
        if (!root.armed || !Power.on_ac) {
            rest.stop();
            if (root.phase === "idle") Style.preview(name);
            return;
        }
        if (now) root.settle();
        else rest.restart();
    }

    // Saves `name` as the style and shows it.
    function commit(name) {
        const saved = Style.save_choice(name);
        if (saved !== "") root.show(saved, true);
    }

    function settle() {
        rest.stop();
        if (root.phase === "cover" || Style.name === root.target) return;
        if (!Power.on_ac) {
            Style.preview(root.target);
            return;
        }
        const kind = Kinds.kind_for(root.target);
        root.phase = "cover";
        mid.interval = Kinds.cover(kind);
        end.interval = Kinds.cover(kind) + Kinds.reveal(kind);
        mid.restart();
        end.restart();
        root.play(kind, 0);
    }

    // Plays a kind or a style's transition without changing the style.
    function request(name, force) {
        if (!force && !Power.on_ac) return;
        root.play(Kinds.kind_for(name), 0);
    }

    Timer {
        id: rest
        interval: 250
        onTriggered: root.settle()
    }

    Timer {
        id: mid
        onTriggered: {
            root.phase = "reveal";
            Style.preview(root.target);
        }
    }

    Timer {
        id: end
        onTriggered: {
            root.phase = "idle";
            if (Style.name !== root.target) root.settle();
        }
    }

    // Survives config reloads, so only a fresh process plays the intro.
    PersistentProperties {
        id: process_state
        reloadableId: "style_transitions"
        property bool started: false

        onLoaded: {
            if (process_state.started) return;
            process_state.started = true;
            root.intro = Power.on_ac;
        }
    }

    // Waits for the bars to map and settle, then reveals the saved style on a fresh start.
    Timer {
        running: true
        interval: 2000
        onTriggered: {
            root.target = Style.name;
            root.armed = true;
            if (!root.intro) return;
            root.intro = false;
            if (!Power.on_ac) {
                root.stop();
                return;
            }
            const kind = Kinds.kind_for(Style.name);
            root.phase = "reveal";
            end.interval = Kinds.reveal(kind);
            end.restart();
            root.play(kind, Kinds.cover(kind));
        }
    }

    IpcHandler {
        target: "transition"

        // Plays a kind or a style's transition on every bar, on battery too.
        function play(name: string): void {
            root.request(name, true);
        }
    }
}
