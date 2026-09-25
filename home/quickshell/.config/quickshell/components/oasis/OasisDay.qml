// home/quickshell/.config/quickshell/components/oasis/OasisDay.qml
import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../theme"
import "../../services"

// One Daily column: icon, a hi/lo range pill, rain chance and the weekday on a horizon; the selected day rises in sand.
Item {
    id: root

    property var day: null
    property bool selected: false
    property real scale_min: 0
    property real scale_max: 1
    // The horizon under the names fades in at the window's first column and out at its last.
    property bool first: false
    property bool last: false
    // Half the gap to the neighbouring columns, so the horizon runs unbroken.
    property real bleed: 2

    readonly property color sand: Theme.theme_secondary
    readonly property color hair: Qt.alpha(Theme.theme_primary, 0.3)
    // The icon art fills about half its box, so the box runs large and gives back its empty margin.
    readonly property int icon_size: Math.max(24, Math.min(48, root.width - 6))
    readonly property int icon_margin: Math.round(root.icon_size * 0.18)
    readonly property int name_h: name.implicitHeight + 11
    readonly property int pop_h: pop.implicitHeight + 4
    readonly property real track_top: icon.y + root.icon_size - root.icon_margin + 4 + hi.implicitHeight + 4
    readonly property real track_bottom: root.height - root.name_h - root.pop_h - lo.implicitHeight - 8
    readonly property real span: Math.max(1, root.scale_max - root.scale_min)

    function y_for(t) {
        return root.track_top + (root.scale_max - t) / root.span * Math.max(1, root.track_bottom - root.track_top);
    }

    Shape {
        visible: root.selected
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width / 2
                centerY: root.height * 0.94
                focalX: centerX
                focalY: centerY
                centerRadius: Math.max(root.width * 0.62, 1)
                focalRadius: 0
                GradientStop { position: 0; color: Qt.alpha(root.sand, 0.14) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { width: root.width; height: root.height }
        }
    }

    Image {
        id: icon
        anchors.horizontalCenter: parent.horizontalCenter
        y: 6 - root.icon_margin
        width: root.icon_size
        height: root.icon_size
        readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
        sourceSize.width: Math.ceil(96 * dpr)
        sourceSize.height: Math.ceil(96 * dpr)
        source: root.day ? WeatherState.icon_source(root.day.code, true) : ""
        smooth: true
        opacity: root.selected ? 1 : 0.85
    }

    readonly property real top_y: root.day ? root.y_for(root.day.max) : root.track_top
    readonly property real bottom_y: root.day ? Math.max(root.top_y + 6, root.y_for(root.day.min)) : root.track_top + 6

    Text {
        id: hi
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.top_y - implicitHeight - 4
        text: root.day ? Math.round(root.day.max) + "°" : ""
        color: root.selected ? Theme.fg_strong : Theme.fg_core
        font.family: Style.number_font
        font.pixelSize: Style.fs(-2)
        font.weight: root.selected ? Font.Medium : Font.Normal
        font.features: { "tnum": 1 }
    }

    Rectangle {
        visible: root.selected
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.top_y - 3
        width: 14
        height: root.bottom_y - root.top_y + 6
        radius: width / 2
        color: Theme.bg_mantle
        border.width: 1
        border.color: Qt.alpha(root.sand, 0.7)
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.top_y
        width: root.selected ? 8 : 6
        height: root.bottom_y - root.top_y
        radius: width / 2
        opacity: root.selected ? 1 : 0.8
        gradient: Gradient {
            GradientStop { position: 0; color: root.selected ? root.sand : Qt.tint(Theme.theme_primary_light, Qt.alpha(root.sand, 0.5)) }
            GradientStop { position: 1; color: root.selected ? Theme.theme_primary : Theme.theme_primary_strong }
        }
    }

    Text {
        id: lo
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.bottom_y + 4
        text: root.day ? Math.round(root.day.min) + "°" : ""
        color: Theme.fg_dim
        font.family: Style.number_font
        font.pixelSize: Style.fs(-3)
        font.features: { "tnum": 1 }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - root.name_h - root.pop_h
        spacing: 4

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 5
            height: 5
            radius: 2.5
            topRightRadius: 0
            rotation: -45
            color: Qt.alpha(Theme.info, 0.8)
        }

        Text {
            id: pop
            text: root.day ? root.day.pop + "%" : ""
            color: Qt.tint(Theme.fg_core, Qt.alpha(Theme.info, 0.75))
            font.family: Style.number_font
            font.pixelSize: Style.fs(-3)
            font.features: { "tnum": 1 }
        }
    }

    Rectangle {
        x: -root.bleed
        y: root.height - root.name_h + 2
        width: root.width + root.bleed * 2
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.first ? "transparent" : root.hair }
            GradientStop { position: 1; color: root.last ? "transparent" : root.hair }
        }
    }

    Rectangle {
        visible: root.selected
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - root.name_h - 1
        width: 11
        height: 11
        radius: 5.5
        color: Theme.bg_mantle

        Rectangle {
            anchors.centerIn: parent
            width: 7
            height: 7
            radius: 3.5
            color: root.sand
        }
    }

    Text {
        id: name
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        text: root.day ? root.day.weekday : ""
        color: root.selected ? root.sand : Theme.fg_dim
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
        font.weight: root.selected ? Font.DemiBold : Font.Medium
    }
}
