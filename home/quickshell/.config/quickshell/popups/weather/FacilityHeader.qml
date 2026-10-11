// home/quickshell/.config/quickshell/popups/weather/FacilityHeader.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// The GoldenEye briefing line over the Daily columns and alerts: the forecast location as the facility.
ColumnLayout {
    id: root

    spacing: 4

    Text {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        elide: Text.ElideRight
        text: "FACILITY: " + (WeatherState.location_name !== "" ? WeatherState.location_name.toUpperCase() : "UNKNOWN")
        color: Style.text_fg
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Qt.alpha(Style.accent_color, 0.3)
    }
}
