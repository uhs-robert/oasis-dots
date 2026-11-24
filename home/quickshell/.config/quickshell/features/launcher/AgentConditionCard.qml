import QtQuick
import qs.theme
import qs.features.keeptabs.views
import "../../core/Fuzzy.js" as Fuzzy

// An agent card in the keeptabs "memcard" layout's Resident Evil look (ConditionAgents): a small heart monitor and the
// condition word in place of the state badge. The rest matches the plain card in AgentsProvider.
Item {
    id: card

    property var entry: ({})
    property var positions: []
    property bool selected: false
    // The last line the session's pane printed (AgentsProvider.tails).
    property string tail: ""
    property bool animating: false

    readonly property var cond: monitor_trace.look

    Text {
        id: title
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.StyledText
        text: Fuzzy.highlight(card.entry.label || "", card.positions, String(Style.text_accent))
        color: Style.text_fg
        font.family: Style.font_family
        font.pixelSize: Style.fs(-1)
        font.bold: true
    }

    Rectangle {
        id: monitor
        anchors.top: title.bottom
        anchors.topMargin: 5
        width: Style.px(72)
        height: Style.px(20)
        radius: 2
        color: Qt.alpha(Theme.bg_shadow, 0.8)
        border.width: 1
        border.color: Qt.alpha(card.cond.color, card.selected ? 0.7 : 0.3)

        ConditionTrace {
            id: monitor_trace
            anchors.fill: parent
            anchors.margins: 3
            run_state: card.entry.state || ""
            running: card.animating
        }
    }

    // The word never elides: it is the card's state. The context bar is shortened to leave it room.
    Text {
        id: word
        anchors.left: monitor.right
        anchors.leftMargin: 8
        anchors.verticalCenter: monitor.verticalCenter
        text: card.cond.word
        textFormat: Text.PlainText
        color: card.cond.color
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        font.bold: true
    }

    AgentContextBar {
        id: card_context
        anchors.right: parent.right
        anchors.verticalCenter: monitor.verticalCenter
        bar_width: Style.px(32)
        context: card.entry.context || null
    }

    Text {
        id: cwd
        anchors.top: monitor.bottom
        anchors.topMargin: 5
        width: parent.width
        elide: Text.ElideMiddle
        text: [card.entry.agent || "", card.entry.cwd_short || ""].filter(s => s !== "").join(" · ")
        textFormat: Text.PlainText
        color: Style.text_muted
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
    }

    Text {
        anchors.top: cwd.bottom
        anchors.topMargin: 3
        width: parent.width
        elide: Text.ElideRight
        text: card.tail
        textFormat: Text.PlainText
        color: Style.text_dim
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-4)
    }
}
