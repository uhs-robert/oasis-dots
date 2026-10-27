import QtQuick
import qs.theme
import "AgentSessions.js" as AgentSessions

// An agent session's state as a small pill, for its card and its list row (AgentSessions.badge_style).
Rectangle {
    id: root

    property string run_state: ""
    readonly property var look: AgentSessions.badge_style(root.run_state)
    readonly property color tone: root.look.tone === "primary" ? Theme.theme_primary : root.look.tone === "ok" ? Theme.ok : root.look.tone === "warning" ? Theme.warning : Style.text_dim

    visible: root.run_state !== ""
    width: badge_text.implicitWidth + 12
    height: badge_text.implicitHeight + 4
    radius: height / 2
    color: root.look.filled ? root.tone : Qt.alpha(root.tone, 0.14)
    border.width: root.look.filled ? 0 : 1
    border.color: Qt.alpha(root.tone, 0.6)

    Text {
        id: badge_text
        anchors.centerIn: parent
        text: root.run_state.toUpperCase()
        color: root.look.filled ? Theme.bg_crust : root.tone
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.bold: true
    }
}
