// home/quickshell/.config/quickshell/popups/weather/SaveIcon.qml
import QtQuick
import "../../theme"
import "../../services"

// A memory card save block: a bordered square holding the weather icon rasterised at 16px and scaled up unsmoothed.
Rectangle {
    id: root

    property real size: 40
    property real code: -1
    property bool is_day: true
    property bool lit: false

    implicitWidth: root.size
    implicitHeight: root.size
    radius: 3
    color: root.lit ? Style.selection_bg : Qt.alpha(Theme.bg_shadow, 0.45)
    border.width: 2
    border.color: root.lit ? Theme.theme_primary_light : Style.frame_border_color

    Image {
        anchors.centerIn: parent
        width: Math.max(16, Math.floor((root.size - 8) / 16) * 16)
        height: width
        sourceSize.width: 16
        sourceSize.height: 16
        source: root.code >= 0 ? WeatherState.icon_source(root.code, root.is_day) : ""
        smooth: false
        mipmap: false
    }
}
