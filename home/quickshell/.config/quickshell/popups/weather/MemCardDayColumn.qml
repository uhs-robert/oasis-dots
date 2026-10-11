// home/quickshell/.config/quickshell/popups/weather/MemCardDayColumn.qml
import QtQuick
import "../../theme"
import "../../services"

// Placeholder for this layout's own Daily column; DailyView keeps it switched off until it draws something.
Item {
    id: root

    property var day: null
    property int day_index: 0
    property string label: ""
    property bool selected: false
    property real col_w: 0
    // The week's coldest low and warmest high, shared by every column so ranges compare across days.
    property real scale_min: 0
    property real scale_max: 1
}
