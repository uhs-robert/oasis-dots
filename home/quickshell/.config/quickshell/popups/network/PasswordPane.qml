// home/quickshell/.config/quickshell/popups/network/PasswordPane.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"

ColumnLayout {
    id: root

    property var st
    property string target_name: ""
    property string text: ""
    property bool reveal: false
    property string status_text: ""
    property bool active: false

    signal edited(string t)
    signal toggle_reveal()
    signal submit()
    signal cancel()

    spacing: 8

    Text {
        text: root.target_name ? "Password for " + root.target_name : ""
        color: root.st.text_strong
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-1)
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.px(26)
        radius: Style.radius(4)
        color: Style.pal.bg_surface

        TextInput {
            id: password_input
            anchors.fill: parent
            anchors.margins: 6
            focus: root.active
            echoMode: root.reveal ? TextInput.Normal : TextInput.Password
            color: root.st.text_fg
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-1)
            text: root.text
            onTextChanged: root.edited(text)

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Tab) {
                    root.toggle_reveal();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.submit();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.cancel();
                    event.accepted = true;
                }
            }
        }
    }

    MenuFooter {
        Layout.fillWidth: true
        text: "Tab show/hide · Enter connect · Esc cancel"
    }

    Text {
        visible: root.status_text !== ""
        text: root.status_text
        color: root.st.text_muted
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
