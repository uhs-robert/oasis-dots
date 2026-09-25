// home/quickshell/.config/quickshell/popups/snes/SnesClockStatus.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components/snes" as Snes
import "../../theme"
import "../../services"

// The clock as an FF6 status window: DATE and TIME rows, ticking by the minute while shown.
Item {
    id: root

    property bool running: false
    readonly property date now: Timezones.shift(clock.date)

    implicitHeight: rows.implicitHeight + 20 + status_window.drop

    SystemClock {
        id: clock
        enabled: root.running
        precision: SystemClock.Minutes
    }

    Snes.SnesWindow {
        id: status_window
        anchors.fill: parent
    }

    ColumnLayout {
        id: rows
        x: 12
        y: 10
        width: root.width - 24 - status_window.drop
        spacing: 4

        Repeater {
            model: [["DATE", Qt.formatDate(root.now, "ddd MMM d yyyy")], ["TIME", Qt.formatTime(root.now, "HH:mm") + (Timezones.abbrev !== "" ? " " + Timezones.abbrev : "")]]

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: parent.modelData[0]
                    color: Theme.theme_primary_light
                    style: Text.Raised
                    styleColor: Style.text_shadow
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - 2
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    text: parent.modelData[1]
                    color: Theme.fg_strong
                    style: Text.Raised
                    styleColor: Style.text_shadow
                    font.family: Style.number_font
                    font.pixelSize: Style.font_size
                }
            }
        }
    }
}
