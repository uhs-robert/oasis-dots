pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../services"
import "Kinds.js" as Kinds

// Plays a one-shot transition when the displayed style changes and rests; commits of the shown style never replay.
Singleton {
    id: root

    signal play(string kind)

    property bool armed: false
    // The style the bars last transitioned to.
    property string shown: ""

    function request(name, force) {
        if (!force && !Power.on_ac) return;
        root.play(Kinds.kind_for(name));
    }

    // Plays the displayed style now if it differs from the one shown.
    function settle() {
        rest.stop();
        if (!root.armed || Style.name === root.shown) return;
        root.shown = Style.name;
        root.request(Style.name, false);
    }

    Connections {
        target: Style
        function onNameChanged() {
            if (!root.armed) return;
            if (Style.name === root.shown) rest.stop();
            else rest.restart();
        }
        function onSaved_nameChanged() {
            if (Style.name === Style.saved_name) root.settle();
        }
    }

    Timer {
        id: rest
        interval: 250
        onTriggered: root.settle()
    }

    // Survives config reloads, so only a fresh process plays the intro.
    PersistentProperties {
        id: process_state
        reloadableId: "style_transitions"
        property bool started: false
    }

    // Waits for the bars to map and settle; a fresh start then plays the saved style once.
    Timer {
        running: true
        interval: 2000
        onTriggered: {
            root.shown = Style.name;
            root.armed = true;
            if (process_state.started) return;
            process_state.started = true;
            root.request(Style.name, false);
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
