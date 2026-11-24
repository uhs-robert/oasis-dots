import QtQuick
import qs.theme
import "Condition.js" as Condition

// An EcgTrace that picks its beat and colour from a session state, for surfaces outside keeptabs (the agent picker's
// cards). `look` gives the condition word and colour to draw beside it.
Item {
    id: root

    property string run_state: ""
    property bool running: false
    property real line_width: Style.px(1.5)
    property color dim_color: Style.text_dim
    readonly property var look: Condition.look(root.run_state, { warning: Style.pal.warning, ok: Style.pal.ok, info: Style.pal.info, dim: root.dim_color })

    EcgTrace {
        anchors.fill: parent
        beat: root.look.beat
        line_color: root.look.color
        line_width: root.line_width
        beat_ms: root.look.ms
        running: root.running
    }
}
