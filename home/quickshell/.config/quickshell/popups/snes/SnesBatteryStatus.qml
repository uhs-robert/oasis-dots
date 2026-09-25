// home/quickshell/.config/quickshell/popups/snes/SnesBatteryStatus.qml
import QtQuick
import QtQuick.Layouts
import "../../components/snes" as Snes
import "../../theme"

// The battery as an FF6 status line: "BAT 82/100" over a gauge, then state, time and rate in a blue window.
Item {
    id: root

    property real percent: 0
    property string state_label: ""
    property string time_label: ""
    property real rate: 0
    readonly property bool low: root.percent <= 20

    implicitHeight: status.implicitHeight + 20 + menu_window.drop

    Snes.SnesWindow {
        id: menu_window
        anchors.fill: parent
    }

    ColumnLayout {
        id: status
        x: 12
        y: 10
        width: root.width - 24 - menu_window.drop
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "BAT"
                color: Theme.theme_primary_light
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: Math.round(root.percent)
                color: root.low ? Theme.theme_label : Theme.fg_strong
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.number_font
                font.pixelSize: Style.fs(4)
            }

            Text {
                text: "/100"
                color: Theme.fg_strong
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.number_font
                font.pixelSize: Style.fs(-2)
            }
        }

        Snes.SnesGauge {
            Layout.fillWidth: true
            implicitHeight: 9
            value: root.percent / 100
            fill_color: root.low ? Theme.theme_label : Theme.theme_primary_strong
            shade_color: root.low ? Qt.tint(Theme.theme_label, Qt.alpha(Theme.fg_strong, 0.4)) : Qt.tint(Theme.theme_primary_light, Qt.alpha(Theme.fg_strong, 0.3))
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 8

            Text {
                text: root.state_label
                color: Theme.theme_secondary
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: root.time_label
                color: Theme.fg_strong
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }
        }

        RowLayout {
            visible: root.rate > 0
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "RATE"
                color: Theme.theme_primary_light
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: root.rate.toFixed(1) + " W"
                color: Theme.fg_strong
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }
        }
    }
}
