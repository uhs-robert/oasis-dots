// home/quickshell/.config/quickshell/components/modern/DayColumn.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

// One Daily column: day pill, icon, high, the week-scaled range track, low and rain chance; raised when selected.
Item {
    id: root

    property var day: null
    property string label: ""
    property bool selected: false
    property real scale_min: 0
    property real scale_max: 1

    readonly property real span: Math.max(1, root.scale_max - root.scale_min)

    CardSurface {
        visible: root.selected
        anchors.fill: parent
        selected: true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 8
        anchors.bottomMargin: 10
        spacing: 6

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Math.min(root.width - 4, day_text.implicitWidth + 14)
            implicitHeight: day_text.implicitHeight + 4
            radius: height / 2
            color: "transparent"
            gradient: root.selected ? pill_gradient : null

            Gradient {
                id: pill_gradient
                GradientStop { position: 0; color: Style.selection_shade.a > 0 ? Style.selection_shade : Style.selection_bg }
                GradientStop { position: 1; color: Style.selection_bg }
            }

            Text {
                id: day_text
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 4)
                elide: Text.ElideRight
                text: root.label
                color: root.selected ? Style.selection_fg : Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
                font.weight: Font.DemiBold
            }
        }

        // The icon art fills about half its box, so the box runs large and gives back its empty margin.
        Image {
            readonly property real size: Math.max(24, Math.min(48, root.width - 6))
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: size
            Layout.preferredHeight: size
            Layout.topMargin: -Math.round(size * 0.18)
            Layout.bottomMargin: -Math.round(size * 0.18)
            readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
            sourceSize.width: Math.ceil(96 * dpr)
            sourceSize.height: Math.ceil(96 * dpr)
            source: root.day ? WeatherState.icon_source(root.day.code, true) : ""
            smooth: true
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.day ? Math.round(root.day.max) + "°" : ""
            color: Style.text_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(1)
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.minimumHeight: 48
            Layout.maximumHeight: 150
            implicitWidth: 6

            Rectangle {
                id: track
                anchors.fill: parent
                radius: 3
                color: Qt.alpha(Theme.fg_core, 0.08)
            }

            Rectangle {
                readonly property real top_f: root.day ? (root.scale_max - root.day.max) / root.span : 0
                readonly property real bottom_f: root.day ? (root.scale_max - root.day.min) / root.span : 1
                width: track.width
                y: track.height * top_f
                height: Math.max(width, track.height * (bottom_f - top_f))
                radius: 3
                opacity: root.selected ? 1 : 0.7
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.tint(Theme.theme_primary_light, Qt.alpha(Theme.theme_secondary, 0.75)) }
                    GradientStop { position: 1; color: Theme.theme_primary }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.day ? Math.round(root.day.min) + "°" : ""
            color: root.selected ? Style.text_dim : Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.day ? "\u{f058c} " + root.day.pop + "%" : ""
            color: Qt.tint(Style.text_dim, Qt.alpha(Theme.info, 0.7))
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-4)
        }
    }
}
