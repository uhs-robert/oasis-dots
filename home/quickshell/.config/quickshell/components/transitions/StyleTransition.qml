pragma ComponentBehavior: Bound
import QtQuick
import "Kinds.js" as Kinds

// Overlay for one bar window; the effect is only built while a transition plays.
Item {
    id: root

    required property Item target
    property bool shown: true
    property string kind: "fade"
    property int start_at: 0

    function play(kind, start_at) {
        loader.active = false;
        if (!root.shown || root.width <= 0 || root.height <= 0) return;
        root.kind = kind;
        root.start_at = start_at;
        loader.active = true;
    }

    // Keeps the bar blank until the intro reveals it.
    function hold_intro() {
        root.play("fade", Kinds.cover("fade"));
    }

    Component.onCompleted: if (Transitions.intro) root.hold_intro()

    Connections {
        target: Transitions
        function onPlay(kind, start_at) {
            root.play(kind, start_at);
        }
        function onStop() {
            loader.active = false;
        }
        function onIntroChanged() {
            if (Transitions.intro) root.hold_intro();
        }
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: false
        sourceComponent: Kinds.is_texture(root.kind) ? texture_fx : cover_fx
    }

    Component {
        id: texture_fx
        TextureFx {
            target: root.target
            kind: root.kind
            cover: Kinds.cover(root.kind)
            reveal: Kinds.reveal(root.kind)
            start_at: root.start_at
            hold: Transitions.intro
            onFinished: loader.active = false
        }
    }

    Component {
        id: cover_fx
        CoverFx {
            target: root.target
            kind: root.kind
            cover: Kinds.cover(root.kind)
            reveal: Kinds.reveal(root.kind)
            start_at: root.start_at
            hold: Transitions.intro
            onFinished: loader.active = false
        }
    }
}
