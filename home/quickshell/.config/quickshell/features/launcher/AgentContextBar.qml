import QtQuick
import qs.theme
import "AgentSessions.js" as AgentSessions

// How full an agent session's context is, as tokens ("118k / 200k") and a thin bar coloured by fill
// (AgentSessions.context_tone), for its card and its list row. Hidden for a session without context data.
Item {
    id: root

    // { pct, used, window } from AgentSessions.parse_context, or null.
    property var context: null
    property real bar_width: Style.px(64)
    readonly property string tone_name: root.context ? AgentSessions.context_tone(root.context.pct) : "ok"
    readonly property color tone: root.tone_name === "error" ? Theme.error : root.tone_name === "warning" ? Theme.warning : Theme.ok

    visible: !!root.context
    implicitWidth: tokens.implicitWidth + 6 + root.bar_width
    implicitHeight: tokens.implicitHeight

    Text {
        id: tokens
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.context ? AgentSessions.context_label(root.context) : ""
        textFormat: Text.PlainText
        color: Style.text_muted
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-5)
    }

    Rectangle {
        id: track
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.bar_width
        height: Style.px(4)
        radius: height / 2
        color: Qt.alpha(root.tone, 0.18)

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.context ? parent.width * Math.max(0, Math.min(1, root.context.pct / 100)) : 0
            radius: parent.radius
            color: root.tone
        }
    }
}
