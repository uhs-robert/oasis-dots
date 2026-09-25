// home/quickshell/.config/quickshell/components/modern/WeatherHero.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import ".."
import "../../services"

// Current conditions as a large temperature beside the condition, then the first alert as a tinted card.
ColumnLayout {
    id: root

    signal alert_clicked()

    readonly property bool has_alert: WeatherState.alerts.length > 0
    readonly property var alert: root.has_alert ? WeatherState.alerts[0] : null

    spacing: 12

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 2
        spacing: 16

        Row {
            Layout.alignment: Qt.AlignVCenter

            Text {
                id: temp_text
                text: WeatherState.has_data ? Math.round(WeatherState.current.temp) : "--"
                color: Style.text_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(42)
                font.weight: Font.Medium
                font.letterSpacing: -3
                font.features: { "tnum": 1 }
            }

            Text {
                y: Math.round(temp_text.height * 0.16)
                leftPadding: 2
                text: "°" + WeatherState.unit_symbol()
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(3)
                font.weight: Font.Medium
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Image {
                    visible: WeatherState.has_data
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    Layout.topMargin: -6
                    Layout.bottomMargin: -6
                    Layout.leftMargin: -5
                    Layout.rightMargin: -3
                    readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                    sourceSize.width: Math.ceil(68 * dpr)
                    sourceSize.height: Math.ceil(68 * dpr)
                    source: WeatherState.has_data ? WeatherState.icon_source(WeatherState.current.code, WeatherState.current.is_day) : ""
                    smooth: true
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: WeatherState.has_data ? WeatherState.current.cond : WeatherState.loading ? "Loading…" : "Unavailable"
                    color: WeatherState.has_data || WeatherState.loading ? Style.text_strong : Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(2)
                    font.weight: Font.DemiBold
                }
            }

            Text {
                visible: WeatherState.has_data
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: WeatherState.has_data ? "Feels like " + Math.round(WeatherState.current.feels) + "°" + WeatherState.unit_symbol() : ""
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }

            Text {
                visible: WeatherState.location_name !== "" || WeatherState.stale
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: WeatherState.stale ? "Stale data" + (WeatherState.error ? ": " + WeatherState.error : "") : WeatherState.location_name
                color: WeatherState.stale ? Theme.warning : Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
            }
        }
    }

    Rectangle {
        visible: root.has_alert
        Layout.fillWidth: true
        implicitHeight: alert_row.implicitHeight + 16
        radius: Style.radius(7)
        border.width: 1
        border.color: Qt.alpha(Theme.theme_label, 0.24)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.tint(Style.frame_shade, Qt.alpha(Theme.theme_label, 0.15)) }
            GradientStop { position: 1; color: Qt.tint(Style.frame_color, Qt.alpha(Theme.theme_label, 0.09)) }
        }

        Sheen {
            color_top: Qt.alpha(Theme.theme_label, 0.3)
            corner: parent.radius
            edge: 1
        }

        RowLayout {
            id: alert_row
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 8
            anchors.rightMargin: 10
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 8
                color: Theme.theme_label

                Text {
                    anchors.centerIn: parent
                    text: "\u{f0026}"
                    color: Theme.bg_crust
                    font.family: Theme.font_family
                    font.pixelSize: 15
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.alert ? root.alert.event + (WeatherState.alerts.length > 1 ? "  +" + (WeatherState.alerts.length - 1) : "") : ""
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-1)
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.alert ? WeatherState.fmt_until(root.alert.ends) : ""
                    color: Style.text_dim
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-4)
                }
            }

            Text {
                text: "\u{f0142}"
                color: Style.text_muted
                font.family: Theme.font_family
                font.pixelSize: 14
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.alert_clicked()
        }
    }
}
