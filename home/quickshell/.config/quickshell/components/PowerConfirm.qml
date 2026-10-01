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

    readonly property bool watch: root.st.confirm_layout === "watch"
    readonly property var words: ({ lock: "LOCK", logout: "LOG OUT", reboot: "RESTART", poweroff: "POWER OFF" })

    function confirm() {
        ThemeAudio.play("confirm");
        root.confirmed();
    }

    function cancel() {
        ThemeAudio.play("cancel");
        root.cancelled();
    }

    function handle_key(event) {
        if (event.key === Qt.Key_Y || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.confirm();
        else if (event.key === Qt.Key_N || event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) root.cancel();
        else return;
        event.accepted = true;
    }

    ColumnLayout {
        visible: root.watch
        spacing: 10

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "ENTER AGAIN TO " + (root.words[root.action] || "CONTINUE")
            color: Style.pal.error
            font.family: root.st.title_font_family
            font.pixelSize: root.st.fs(-5)
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            Repeater {
                model: [{ label: "CONFIRM", on: true }, { label: "CANCEL", on: false }]

                Rectangle {
                    id: box
                    required property var modelData
                    implicitWidth: box_label.implicitWidth + 24
                    implicitHeight: 28
                    color: box.modelData.on ? root.st.selection_bg : "transparent"
                    border.width: 1
                    border.color: box.modelData.on ? root.st.selection_border : Qt.alpha(root.st.selection_border, 0.4)

                    Text {
                        id: box_label
                        anchors.centerIn: parent
                        text: box.modelData.label
                        color: box.modelData.on ? root.st.text_strong : root.st.text_fg
                        font.family: root.st.title_font_family
                        font.pixelSize: root.st.fs(-3)
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: box.modelData.on ? root.confirm() : root.cancel()
                    }
                }
            }
        }
    }

    Text {
        visible: !root.watch
        text: (Power.glyphs[root.action] || "") + " " + (Power.labels[root.action] || "") + "?"
        color: Power.color(root.action, root.st) || root.st.text_fg
        font.family: root.st.font_family
        font.pixelSize: root.st.font_size
    }

    Text {
        visible: !root.watch
        text: "Yes"
        color: Style.pal.ok
        font.family: root.st.font_family
        font.pixelSize: root.st.font_size

        MouseArea {
            anchors.fill: parent
            onClicked: root.confirm()
        }
    }

    Text {
        visible: !root.watch
        text: "No"
        color: Style.pal.error
        font.family: root.st.font_family
        font.pixelSize: root.st.font_size

        MouseArea {
            anchors.fill: parent
            onClicked: root.cancel()
        }
    }
}
