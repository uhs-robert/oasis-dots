// home/quickshell/.config/quickshell/bar/modules/Tray.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"
import "../../services"

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

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: ""
            color: Theme.theme_primary
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_glyph_size
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
