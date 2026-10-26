import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs.theme
import qs.features.bar
import qs.features.popups

BarModule {
    id: root
    module_name: "tray"
    hover_popup: true

    readonly property int count: SystemTray.items.values.length
    readonly property bool needs_attention: SystemTray.items.values.some(i => i.status === Status.NeedsAttention)
    tooltip_text: root.count + " tray app" + (root.count === 1 ? "" : "s")

    shown: root.count > 0
    implicitWidth: root.shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    ModuleRow {
        id: row
        vertical: root.vertical
        spacing: 2

        BarIcon {
            id: chevron
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            ink_centre: root.vertical
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
            visible: root.needs_attention && !root.vertical
            implicitWidth: 5
            implicitHeight: 5
            radius: 2.5
            color: Theme.theme_accent
        }
    }

    // A side bar's column has no room beside the chevron, so the dot sits on its top right, inside the column.
    // A child of the module, not of the chevron, which turns when the popup opens.
    Rectangle {
        visible: root.needs_attention && root.vertical
        x: row.x + chevron.x + chevron.width - width
        y: row.y + chevron.y
        width: 5
        height: 5
        radius: 2.5
        color: Theme.theme_accent
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggle_popup()
    }
}
