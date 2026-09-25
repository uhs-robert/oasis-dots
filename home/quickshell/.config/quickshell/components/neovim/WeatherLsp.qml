// home/quickshell/.config/quickshell/components/neovim/WeatherLsp.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import "../../theme"
import "../../services"

// Weather as a Neovim buffer: a winbar breadcrumb, the conditions, and the first alert as an LSP diagnostic on the location line.
ColumnLayout {
    id: root

    // Breadcrumb parts after "weather", e.g. the tab and its sub-view.
    property var trail: []
    readonly property var alert: WeatherState.alerts.length > 0 ? WeatherState.alerts[0] : null
    readonly property color diag: root.alert ? WeatherState.alert_color(root.alert.severity) : Theme.warning

    signal alert_clicked()

    spacing: 6

    function fmt_temp(t) {
        return Math.round(t) + "°" + WeatherState.unit_symbol();
    }

    Row {
        spacing: 6

        Text {
            text: "\u{f0c2}"
            color: Style.text_primary
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }

        Repeater {
            model: ["weather"].concat(root.trail.filter(t => t !== ""))

            Row {
                id: crumb
                required property string modelData
                required property int index
                readonly property bool last: crumb.index === root.trail.filter(t => t !== "").length
                spacing: 6

                Text {
                    visible: crumb.index > 0
                    text: "›"
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }

                Text {
                    text: crumb.modelData
                    color: crumb.last ? Style.text_fg : Style.text_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                    font.bold: crumb.last
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Image {
            readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
            Layout.preferredWidth: Style.px(48)
            Layout.preferredHeight: Style.px(48)
            visible: WeatherState.has_data
            source: WeatherState.has_data ? WeatherState.icon_source(WeatherState.current.code, WeatherState.current.is_day) : ""
            sourceSize.width: Math.ceil(96 * dpr)
            sourceSize.height: Math.ceil(96 * dpr)
            smooth: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Row {
                spacing: 10

                Text {
                    id: temp_text
                    text: WeatherState.has_data ? root.fmt_temp(WeatherState.current.temp) : "--°"
                    color: Style.text_strong
                    font.family: Style.number_font
                    font.pixelSize: Style.fs(15)
                    font.bold: true
                }

                Text {
                    anchors.baseline: temp_text.baseline
                    text: WeatherState.has_data ? WeatherState.current.cond : WeatherState.loading ? "Loading…" : "Unavailable"
                    color: WeatherState.has_data || WeatherState.loading ? Style.text_fg : Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-1)
                }
            }

            Text {
                visible: WeatherState.has_data
                text: "Feels like " + (WeatherState.has_data ? root.fmt_temp(WeatherState.current.feels) : "") + (WeatherState.stale ? "  ·  stale" : "")
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }
    }

    Item {
        visible: WeatherState.location_name !== ""
        Layout.fillWidth: true
        implicitHeight: location_text.implicitHeight + 4

        Text {
            visible: !!root.alert
            width: 22
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: location_text.verticalCenter
            text: "\u{f071}"
            color: root.diag
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }

        Text {
            id: location_text
            x: 30
            width: Math.min(implicitWidth, parent.width - x)
            elide: Text.ElideRight
            text: WeatherState.location_name
            color: Style.text_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
        }

        // Undercurl, drawn once.
        Shape {
            visible: !!root.alert
            x: location_text.x
            y: location_text.y + location_text.height
            width: location_text.width
            height: 4

            ShapePath {
                strokeColor: root.diag
                strokeWidth: 1
                fillColor: "transparent"
                PathSvg {
                    path: {
                        let d = "M0 2";
                        for (let x = 0; x < location_text.width; x += 4) d += " Q" + (x + 1) + " 0 " + (x + 2) + " 2 Q" + (x + 3) + " 4 " + (x + 4) + " 2";
                        return d;
                    }
                }
            }
        }
    }

    Row {
        visible: !!root.alert
        Layout.leftMargin: 30
        Layout.fillWidth: true
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "└──"
            color: Qt.tint(Style.frame_color, Qt.alpha(root.diag, 0.55))
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(event_text.implicitWidth, Math.max(40, root.width - 150)) + 14
            height: event_text.implicitHeight + 2
            radius: 3
            color: Qt.alpha(root.diag, 0.13)

            Text {
                id: event_text
                anchors.centerIn: parent
                width: parent.width - 14
                elide: Text.ElideRight
                text: root.alert ? "■ " + root.alert.event + (WeatherState.alerts.length > 1 ? "  +" + (WeatherState.alerts.length - 1) : "") : ""
                color: root.diag
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.alert ? WeatherState.fmt_until(root.alert.ends) : ""
            color: Qt.tint(Style.text_dim, Qt.alpha(root.diag, 0.6))
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
        }

        TapHandler {
            onTapped: root.alert_clicked()
        }
    }
}
