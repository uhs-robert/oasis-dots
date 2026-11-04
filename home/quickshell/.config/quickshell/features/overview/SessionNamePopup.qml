pragma ComponentBehavior: Bound
import QtQuick
import qs.theme
import qs.features.audio

// Names the session being saved; Enter saves and Esc goes back to marking.
Item {
    id: root

    // A saved session is being replaced rather than a new one named.
    property bool updating: false
    property string error_text: ""
    property bool pending: false
    property int window_count: 0
    readonly property string name: name_input.text.trim()

    signal edited
    signal cancelled
    signal confirmed

    function open(initial_name) {
        name_input.text = initial_name;
        name_input.forceActiveFocus();
        name_input.selectAll();
    }

    // The field is inside a focus scope: unless it gives up its scoped focus, focusing the overview's keys hands it
    // straight back and keys go nowhere.
    function release() {
        name_input.focus = false;
    }

    MouseArea {
        anchors.fill: parent
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.bg_crust, 0.6)
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.px(40), Style.px(440))
        height: name_column.implicitHeight + Style.px(28)
        radius: Style.radius(8)
        color: Theme.bg_mantle
        border.width: 1
        border.color: Style.caret_color

        Column {
            id: name_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.px(14)
            spacing: Style.px(8)

            Text {
                text: root.updating ? "Update session" : "Name this session"
                color: Style.text_primary
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }

            Rectangle {
                width: parent.width
                height: Style.px(30)
                radius: 6
                color: "transparent"
                border.width: 1
                border.color: root.error_text !== "" ? Style.text_primary : Style.text_accent

                TextInput {
                    id: name_input
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    maximumLength: 64
                    clip: true
                    color: Style.text_fg
                    selectionColor: Style.selection_bg
                    selectedTextColor: Style.selection_inverse ? Style.selection_fg : Style.text_fg
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size
                    onTextEdited: root.edited()

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            ThemeAudio.play("cancel");
                            root.cancelled();
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            ThemeAudio.play("confirm");
                            root.confirmed();
                        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_U) {
                            name_input.text = "";
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }
            }

            Text {
                width: parent.width
                text: root.error_text !== "" ? root.error_text : root.pending ? "Saving..." : root.window_count + " window" + (root.window_count === 1 ? "" : "s") + " · Enter save · Esc back to marking"
                wrapMode: Text.WordWrap
                color: root.error_text !== "" ? Style.text_primary : Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
            }
        }
    }
}
