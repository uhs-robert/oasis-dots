import QtQuick
import QtQuick.Effects
import Quickshell
import qs.theme
import qs.services

// A weather condition icon, recolored to `tint` when it is not transparent (Style.weather_icon_tint by default).
Item {
    id: root

    property int code: 0
    property bool is_day: true
    property real size: 24
    property color tint: Style.weather_icon_tint
    readonly property bool tinted: root.tint.a > 0

    implicitWidth: root.size
    implicitHeight: root.size

    Image {
        id: icon_image
        anchors.fill: parent
        visible: !root.tinted
        readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
        sourceSize.width: Math.ceil(2 * root.size * dpr)
        sourceSize.height: Math.ceil(2 * root.size * dpr)
        source: WeatherState.icon_source(root.code, root.is_day)
        smooth: true
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.tinted
        source: icon_image
        colorization: 1
        colorizationColor: root.tint
    }
}
