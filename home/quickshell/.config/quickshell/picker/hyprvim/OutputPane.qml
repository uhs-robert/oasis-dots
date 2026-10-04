// home/quickshell/.config/quickshell/picker/hyprvim/OutputPane.qml
import QtQuick
import "../../services"

// Scrollable read-only output for a prompt of kind "output".
FocusScope {
    id: root

    property var st
    property string label: ""
    property string text: ""
    property real max_height: 0

    readonly property real content_height: view.contentHeight
    readonly property real label_height: label_text.height

    function scroll(dy) {
        const max = Math.max(0, view.contentHeight - view.height);
        view.contentY = Math.max(0, Math.min(max, view.contentY + dy));
    }

    function to_top() {
        view.contentY = 0;
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const k = event.key;
        const line = root.st.fs(4);
        if (k === Qt.Key_Return || k === Qt.Key_Enter) Popups.close();
        else if (k === Qt.Key_J || k === Qt.Key_Down) root.scroll(line);
        else if (k === Qt.Key_K || k === Qt.Key_Up) root.scroll(-line);
        else if (ctrl && k === Qt.Key_D || k === Qt.Key_PageDown) root.scroll(view.height / 2);
        else if (ctrl && k === Qt.Key_U || k === Qt.Key_PageUp) root.scroll(-view.height / 2);
        else return;
        event.accepted = true;
    }

    Text {
        id: label_text
        width: parent.width
        elide: Text.ElideRight
        text: root.label
        color: root.st.text_accent
        font.family: root.st.mono_font
        font.pixelSize: root.st.fs(-2)
        font.bold: true
    }

    Flickable {
        id: view
        y: label_text.height + 8
        width: parent.width
        height: Math.min(view.contentHeight + 8, root.max_height)
        clip: true
        contentWidth: width
        contentHeight: body_text.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Text {
            id: body_text
            width: view.width
            textFormat: Text.PlainText
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            text: root.text
            color: root.st.text_fg
            font.family: root.st.mono_font
            font.pixelSize: root.st.fs(-3)
        }
    }
}
