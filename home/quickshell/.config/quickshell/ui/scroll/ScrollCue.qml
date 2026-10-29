import QtQuick
import QtQuick.Effects
import qs.theme
import "ScrollCue.js" as Cue

// Fades a Flickable's content out at the edges that hide more, with a small caret beside each such edge, so a list
// that continues past the panel shows it. Place it as a sibling of `target`, after it; it covers the same area,
// passes every click through and changes nothing while the content fits.
// It fades the content's alpha instead of painting a colour over it, so it never has to know what the list sits on
// (frame shades, drawer strips, lcd gradients, translucent islands). Only `st` tokens: no style branching here.
Item {
    id: root

    required property Flickable target
    property var st: Style
    // Callers that scroll to a row keep it clear of the fades by this much (ScrollCue.js reveal_target).
    property real fade_height: Style.px(20)
    // Clear space right of the target (up to a divider or the panel edge). The carets sit centred in it, outside the
    // faded content and off every row's text; with no room they fall back inside the target's right end.
    property real gutter: 0

    readonly property var edges: Cue.hidden_edges(root.target.contentY, root.target.height, root.target.contentHeight)
    readonly property bool active: root.edges.top || root.edges.bottom

    x: root.target.x
    y: root.target.y
    width: root.target.width
    height: root.target.height
    enabled: false

    // The layer only exists while something is hidden; it is the viewport's size however long the list is.
    Binding {
        target: root.target.layer
        property: "enabled"
        value: root.active
    }
    Binding {
        target: root.target.layer
        property: "effect"
        value: fade_effect
    }

    // A Binding does not restore its target when it is destroyed, so a cue unloaded before its target (the browse
    // picker's at the max preview size) would leave the layer holding the deleted fade_effect. The next cue's Binding
    // then reads that dangling pointer as the value to restore, and qs segfaults.
    Component.onDestruction: {
        if (!root.target) return;
        root.target.layer.enabled = false;
        root.target.layer.effect = null;
    }

    Component {
        id: fade_effect
        MultiEffect {
            maskEnabled: true
            maskSource: alpha_mask
            // A soft mask: the gradient's alpha eases through a smoothstep S-curve instead of cutting at a threshold.
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    Item {
        id: alpha_mask
        width: root.width
        height: root.height
        visible: false
        layer.enabled: true

        Rectangle {
            id: top_fade
            width: parent.width
            height: root.edges.top ? root.fade_height : 0
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: "white" }
            }
        }
        Rectangle {
            y: top_fade.height
            width: parent.width
            height: parent.height - top_fade.height - bottom_fade.height
            color: "white"
        }
        Rectangle {
            id: bottom_fade
            y: parent.height - height
            width: parent.width
            height: root.edges.bottom ? root.fade_height : 0
            gradient: Gradient {
                GradientStop { position: 0; color: "white" }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    function caret_x(caret_width) {
        return root.gutter >= caret_width ? root.width + (root.gutter - caret_width) / 2 : root.width - caret_width;
    }

    Text {
        visible: root.edges.top
        x: root.caret_x(width)
        anchors.top: parent.top
        text: "▲"
        color: root.st.text_muted
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-5)
    }

    Text {
        visible: root.edges.bottom
        x: root.caret_x(width)
        anchors.bottom: parent.bottom
        text: "▼"
        color: root.st.text_muted
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-5)
    }
}
