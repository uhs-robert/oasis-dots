pragma ComponentBehavior: Bound
import QtQuick
import qs.theme.transitions
import "../../../theme/transitions/Kinds.js" as Kinds

// A style's bar transition played over one popup body for a hover swap, picked like StyleTransition picks it. The
// outgoing popup plays the cover half and the incoming one the reveal half, held covered while the outgoing one covers,
// so the two windows run the bar's one timeline at `time_scale` of its length.
Item {
    id: root

    required property Item target
    property string kind: "fade"
    property real time_scale: 0.5
    // "out" covers the body, "in" reveals it.
    property string phase: "in"

    signal finished()

    readonly property int cover_full: Kinds.cover(root.kind)
    readonly property int reveal_full: Kinds.reveal(root.kind)
    readonly property int cover_ms: Math.round(root.cover_full * root.time_scale)
    property bool holding: root.phase === "in"

    Timer {
        running: root.holding
        interval: root.cover_ms
        onTriggered: root.holding = false
    }

    Loader {
        anchors.fill: parent
        sourceComponent: Kinds.is_texture(root.kind) ? texture_fx : cover_fx
    }

    Component {
        id: texture_fx
        TextureFx {
            target: root.target
            kind: root.kind
            cover: root.cover_full
            reveal: root.reveal_full
            start_at: root.phase === "in" ? root.cover_full : 0
            stop_at: root.phase === "in" ? root.cover_full + root.reveal_full : root.cover_full
            time_scale: root.time_scale
            hold: root.holding
            onFinished: root.finished()
        }
    }

    Component {
        id: cover_fx
        CoverFx {
            target: root.target
            kind: root.kind
            cover: root.cover_full
            reveal: root.reveal_full
            start_at: root.phase === "in" ? root.cover_full : 0
            stop_at: root.phase === "in" ? root.cover_full + root.reveal_full : root.cover_full
            time_scale: root.time_scale
            hold: root.holding
            onFinished: root.finished()
        }
    }
}
