// home/quickshell/.config/quickshell/popups/weather/MissionHeader.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// The GoldenEye briefing line over the Daily columns and alert objectives, with the forecast location as the facility.
ColumnLayout {
    id: root

    readonly property string facility: "FACILITY: " + (WeatherState.location_name !== "" ? WeatherState.location_name.toUpperCase() : "UNKNOWN")
    readonly property bool one_line: root.width >= mission.implicitWidth + grid.columnSpacing + facility_metrics.advanceWidth("· " + root.facility)

    spacing: 4

    FontMetrics {
        id: facility_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
    }

    GridLayout {
        id: grid
        Layout.fillWidth: true
        columns: root.one_line ? 2 : 1
        columnSpacing: 6
        rowSpacing: 1

        Text {
            id: mission
            text: "MISSION 04: WEATHER"
            color: Style.accent_color
            font.family: Style.title_font_family
            font.pixelSize: Style.fs(-6)
            font.letterSpacing: 1
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            elide: Text.ElideRight
            text: (root.one_line ? "· " : "") + root.facility
            color: Style.text_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Qt.alpha(Style.accent_color, 0.3)
    }
}
