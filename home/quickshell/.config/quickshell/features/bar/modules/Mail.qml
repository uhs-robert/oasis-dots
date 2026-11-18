import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.features.mail
import qs.features.bar

BarModule {
    id: root
    module_name: "mail"
    hover_popup: true

    // Nothing to say while Thunderbird or its bridge is off, or while nothing is unread. A refusal shows, because it names the setting to turn on.
    shown: MailState.refused || (MailState.ok && MailState.total > 0)
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    tooltip_text: MailState.refused ? MailState.message : MailState.total + " unread"

    ModuleRow {
        id: row
        vertical: root.vertical
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined

        BadgedGlyph {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            vertical: root.vertical
            cross: root.cross
            icon_name: "mail"
            glyph: "\u{f01ee}"
            count: MailState.refused ? "!" : MailState.total > 99 ? "99+" : String(MailState.total)
            tint: MailState.refused ? Theme.warning : Theme.yellow
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) MailState.refresh();
            else root.toggle_popup();
        }
    }
}
