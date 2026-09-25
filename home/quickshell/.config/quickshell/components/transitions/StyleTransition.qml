pragma ComponentBehavior: Bound
import QtQuick
import "Kinds.js" as Kinds

// Overlay for one bar window; the effect is only built while a transition plays.
Item {
    id: root

    required property Item target
    property bool shown: true
    property string kind: "fade"

    function play(kind) {
        loader.active = false;
        if (!root.shown || root.width <= 0 || root.height <= 0) return;
        root.kind = kind;
        loader.active = true;
    }

    Connections {
        target: Transitions
        function onPlay(kind) {
            root.play(kind);
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
            duration: Kinds.duration(root.kind)
            onFinished: loader.active = false
        }
    }

    Component {
        id: cover_fx
        CoverFx {
            target: root.target
            kind: root.kind
            duration: Kinds.duration(root.kind)
            onFinished: loader.active = false
        }
    }
}
