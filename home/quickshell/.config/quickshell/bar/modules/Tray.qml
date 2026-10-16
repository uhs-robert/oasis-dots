import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"
import "../../services"
import "../../components/bar_icons"

BarModule {
    id: root
    module_name: "tray"

    readonly property int count: SystemTray.items.values.length
    readonly property bool needs_attention: SystemTray.items.values.some(i => i.status === Status.NeedsAttention)
    tooltip_text: root.count + " tray app" + (root.count === 1 ? "" : "s")

    shown: root.count > 0
    implicitWidth: root.shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        spacing: 2

        BarIcon {
            Layout.alignment: Qt.AlignVCenter
            name: "tray"
            variant: "chevron"
            glyph: ""
            tint: Theme.theme_primary
            rotation: Popups.open_name === "tray" ? -90 : 0

            Behavior on rotation {
                NumberAnimation { duration: 180; easing.type: Easing.InOutCubic }
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignTop
            visible: root.needs_attention
            implicitWidth: 5
            implicitHeight: 5
            radius: 2.5
            color: Theme.theme_accent
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggle_popup()
    }
}
