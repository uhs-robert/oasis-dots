// home/quickshell/.config/quickshell/popups/weather/AnnouncementBanner.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// The first active alert as a Black Mesa Announcement System bulletin.
Rectangle {
    id: root

    property var on_open: function () {}
    readonly property var alert: WeatherState.alerts.length > 0 ? WeatherState.alerts[0] : null
    readonly property color red: Theme.theme_label
    readonly property var weekday_names: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    function until(iso) {
        if (!iso) return "";
        const d = new Date(iso);
        const shifted = new Date(d.getTime() + WeatherState.utc_offset * 1000);
        const day = shifted.toISOString().substr(0, 10) === WeatherState.location_date_str() ? "" : root.weekday_names[shifted.getUTCDay()] + " ";
        return "UNTIL " + day + WeatherState.fmt_location_time(d).toUpperCase();
    }

    implicitHeight: column.implicitHeight + 2
    color: Qt.alpha(root.red, 0.06)
    border.width: 1
    border.color: Qt.alpha(root.red, 0.6)

    ColumnLayout {
        id: column
        x: 1
        y: 1
        width: parent.width - 2
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: head_text.implicitHeight + 4
            color: Qt.alpha(root.red, 0.85)

            Text {
                id: head_text
                x: 8
                width: parent.width - 16
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: "BLACK MESA ANNOUNCEMENT SYSTEM"
                color: Theme.bg_crust
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 6
                font.bold: true
                font.letterSpacing: root.width >= 300 ? 2.8 : 1
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 4
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 8

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.alert ? root.alert.event + (WeatherState.alerts.length > 1 ? "  +" + (WeatherState.alerts.length - 1) : "") : ""
                color: root.red
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 3
                font.weight: Font.DemiBold
            }

            Text {
                visible: root.alert && root.alert.ends && root.width >= 260
                text: root.alert ? root.until(root.alert.ends) : ""
                color: root.red
                font.family: Style.number_font
                font.pixelSize: Style.font_size - 4
                font.bold: true
                font.letterSpacing: 0.7
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.on_open()
    }
}
