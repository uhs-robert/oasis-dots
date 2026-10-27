import QtQuick
import qs.theme
import "ScrollCue.js" as Cue

// Edge fades with a small caret over a Flickable's clipped edges, so a list that continues past the panel shows it.
// Place it as a sibling of `target`, above it; it covers the same area, passes every click through and shows
// nothing while the content fits. Only `st` tokens: a style restyles it through them, never by branching here.
Item {
    id: root

    required property Flickable target
    property var st: Style
    // What the content sits on at the target's top and bottom edges; a gradient panel passes its two ends.
    property color top_color: root.st.frame_color
    property color bottom_color: root.st.frame_color
    // Callers that scroll to a row keep it clear of the bottom fade by this much (ScrollCue.js reveal_target).
    property real fade_height: Style.px(20)

    readonly property var edges: Cue.hidden_edges(root.target.contentY, root.target.height, root.target.contentHeight)

    x: root.target.x
    y: root.target.y
    width: root.target.width
    height: root.target.height
    z: 5
    enabled: false

    Rectangle {
        visible: root.edges.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.fade_height
        gradient: Gradient {
            GradientStop { position: 0; color: root.top_color }
            GradientStop { position: 1; color: Qt.alpha(root.top_color, 0) }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            text: "▲"
            color: root.st.text_muted
            font.pixelSize: root.st.fs(-5)
        }
    }

    Rectangle {
        visible: root.edges.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.fade_height
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(root.bottom_color, 0) }
            GradientStop { position: 1; color: root.bottom_color }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: "▼"
            color: root.st.text_muted
            font.pixelSize: root.st.fs(-5)
        }
    }
}
