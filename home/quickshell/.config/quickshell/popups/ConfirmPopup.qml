import QtQuick
import QtQuick.Layouts
import qs.components
import qs.ui
import qs.theme
import qs.services
import qs.features.power

// The confirm card: Confirm's question with Yes and No, dropped from the center island like the Power confirm.
Popup {
    id: root

    popup_name: "confirm"
    title: "Confirm"
    // Sized to the question on one line beside Yes and No, wrapping past the cap.
    preferred_width: Math.min(440, Math.max(root.watch ? 260 : 200, question_metrics.width / Style.scale + (root.watch ? 24 : 110)))
    footer_hint: "y/Enter yes · n/Esc no"
    body_height: content.implicitHeight + 24

    readonly property bool watch: root.st.confirm_layout === "watch"

    TextMetrics {
        id: question_metrics
        text: root.watch ? Confirm.question.toUpperCase() : Confirm.question
        font.family: root.watch ? root.st.title_font_family : root.st.font_family
        font.pixelSize: root.watch ? root.st.fs(-5) : root.st.font_size
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: column.implicitHeight
        focus: true

        Keys.onPressed: event => confirm_row.handle_key(event)

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            PowerConfirm {
                id: confirm_row
                Layout.fillWidth: true
                st: root.st
                question: Confirm.question
                onConfirmed: Confirm.answer(true)
                onCancelled: Confirm.answer(false)
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: Confirm.listening
                text: VoxtypeState.recording ? "󰍬 Listening" : "󰔟 Transcribing"
                color: VoxtypeState.recording ? Style.pal.label : Style.pal.warning
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }
        }
    }
}
