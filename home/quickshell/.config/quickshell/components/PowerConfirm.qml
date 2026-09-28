// home/quickshell/.config/quickshell/components/PowerConfirm.qml
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

// The yes/no prompt for a Power action, shared by the Start menu and the keybind popup.
RowLayout {
    id: root

    property var st: Style.for_item(root)
    property string action: ""
    signal confirmed()
    signal cancelled()

    spacing: 12

    function handle_key(event) {
        if (event.key === Qt.Key_Y || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.confirmed();
        else if (event.key === Qt.Key_N || event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) root.cancelled();
        else return;
        event.accepted = true;
    }

    Text {
        text: (Power.glyphs[root.action] || "") + " " + (Power.labels[root.action] || "") + "?"
        color: Power.color(root.action, root.st) || root.st.text_fg
        font.family: root.st.font_family
        font.pixelSize: root.st.font_size
    }

    Text {
        text: "Yes"
        color: Theme.ok
        font.family: root.st.font_family
        font.pixelSize: root.st.font_size

        MouseArea {
            anchors.fill: parent
            onClicked: root.confirmed()
        }
    }

    Text {
        text: "No"
        color: Theme.error
        font.family: root.st.font_family
        font.pixelSize: root.st.font_size

        MouseArea {
            anchors.fill: parent
            onClicked: root.cancelled()
        }
    }
}
