// home/quickshell/.config/quickshell/components/TextBox.qml
import QtQuick
import "../theme"

// A Pokémon-style text box: pixel double border, text that can type itself out, and a ▼ prompt blinking with the caret.
Item {
    id: root

    readonly property var st: Style.for_item(root)

    property string text: ""
    // Light inner ring and outer ring; an alert box sets both to its warning colour.
    property color inner: root.st.shade_3
    property color outer: root.st.shade_2
    property color text_color: root.st.shade_3
    property color prompt_color: root.inner
    property int font_size: root.st.fs(-4)
    property bool rich: false
    // Characters shown while typing; the full text once it reaches the end.
    property real typed: -1
    readonly property bool typing: type_anim.running

    // Types the text once from the start; rich text appears whole.
    function type_out() {
        if (root.rich) return;
        type_anim.stop();
        type_anim.to = root.text.length;
        type_anim.duration = Math.min(2400, root.text.length * 28);
        type_anim.start();
    }

    implicitHeight: sizing.implicitHeight + 22

    NumberAnimation {
        id: type_anim
        target: root
        property: "typed"
        from: 0
        onFinished: root.typed = -1
    }

    PixelBox {
        anchors.fill: parent
        fill: root.st.shade_0
        rings: [root.outer, root.st.shade_0, root.inner]
    }

    Text {
        id: sizing
        visible: false
        width: parent.width - 28
        text: root.text
        textFormat: root.rich ? Text.StyledText : Text.PlainText
        wrapMode: Text.Wrap
        font.family: root.st.font_family
        font.pixelSize: root.font_size
        lineHeight: 1.25
    }

    Text {
        x: 12
        y: 10
        width: sizing.width
        text: root.typed >= 0 && !root.rich ? root.text.slice(0, Math.floor(root.typed)) : root.text
        textFormat: root.rich ? Text.StyledText : Text.PlainText
        wrapMode: Text.Wrap
        color: root.text_color
        font: sizing.font
        lineHeight: 1.25
    }

    Text {
        visible: !root.typing && Style.caret_phase
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 9
        anchors.bottomMargin: 7
        text: "▼"
        color: root.prompt_color
        font.family: "Press Start 2P"
        font.pixelSize: 8
    }
}
