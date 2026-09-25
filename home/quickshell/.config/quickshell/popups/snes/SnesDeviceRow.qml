// home/quickshell/.config/quickshell/popups/snes/SnesDeviceRow.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../components/snes" as Snes
import "../../theme"

// A Bluetooth device as a party member in its own window: name and state, then a BAT gauge (LINK when no battery is reported).
Item {
    id: root

    property var device: null
    property bool selected: false
    signal clicked()

    readonly property bool connected: !!root.device && root.device.connected
    readonly property bool has_battery: !!root.device && root.device.batteryAvailable
    readonly property real level: root.has_battery ? root.device.battery : root.connected ? 1 : 0

    implicitHeight: member.implicitHeight + 16 + menu_window.drop

    Snes.SnesWindow {
        id: menu_window
        anchors.fill: parent
        lit: root.selected
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }

    HandCursor {
        visible: root.selected
        x: 6
        y: 8 + Math.round((name_text.implicitHeight - height) / 2)
        width: 19
        height: 12
    }

    ColumnLayout {
        id: member
        x: 26
        y: 8
        width: root.width - x - 10 - menu_window.drop
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            RowLabel {
                id: name_text
                Layout.fillWidth: true
                elide: Text.ElideRight
                label: root.device ? root.device.name : ""
                color: root.connected ? Theme.theme_secondary : Theme.fg_strong
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }

            Text {
                text: root.connected ? "Connected" : "Paired"
                color: root.connected ? Theme.theme_primary_light : Style.text_muted
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.preferredWidth: label_metrics.advanceWidth("LINK")
                text: root.has_battery ? "BAT" : "LINK"
                color: Theme.theme_primary_light
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }

            Snes.SnesGauge {
                Layout.fillWidth: true
                implicitHeight: 6
                value: root.level
                dim: !root.connected
            }

            Text {
                Layout.preferredWidth: value_metrics.advanceWidth("100")
                horizontalAlignment: Text.AlignRight
                text: root.has_battery ? Math.round(root.level * 100) : ""
                color: Theme.fg_strong
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }
    }

    FontMetrics {
        id: label_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
    }

    FontMetrics {
        id: value_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
    }
}
