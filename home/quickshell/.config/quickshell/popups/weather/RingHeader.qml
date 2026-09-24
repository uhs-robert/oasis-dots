// home/quickshell/.config/quickshell/popups/weather/RingHeader.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"

// The current conditions as a ticked ring gauge around the temperature, with leader-line callouts beside it.
RowLayout {
    id: root

    readonly property var cur: WeatherState.current
    // The ring fills with the temperature over 0-100 °F in either unit.
    readonly property real fahrenheit: !WeatherState.has_data ? 0 : WeatherState.settings.unit === "celsius" ? root.cur.temp * 9 / 5 + 32 : root.cur.temp

    function fmt_temp(t) {
        return Math.round(t) + "°" + WeatherState.unit_symbol();
    }

    spacing: 6

    RingGauge {
        Layout.preferredWidth: Math.round(Math.max(84, Math.min(112, root.width * 0.34)))
        Layout.preferredHeight: Layout.preferredWidth
        Layout.alignment: Qt.AlignVCenter
        value: Math.max(0, Math.min(1, root.fahrenheit / 100))
        label: WeatherState.has_data ? root.fmt_temp(root.cur.temp) : "--°"
        unit: "NOW"
        label_size: width * 0.24
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignVCenter
        spacing: 6

        Callout {
            Layout.fillWidth: true
            label: "Condition"
            value: WeatherState.has_data ? root.cur.cond : WeatherState.loading ? "Loading…" : "Unavailable"
            value_color: WeatherState.has_data || WeatherState.loading ? Style.text_strong : Theme.warning
        }

        Callout {
            Layout.fillWidth: true
            visible: WeatherState.has_data
            label: "Feels like"
            value: WeatherState.has_data ? root.fmt_temp(root.cur.feels) : ""
        }

        Callout {
            Layout.fillWidth: true
            visible: WeatherState.location_name !== ""
            label: "Location"
            value: WeatherState.location_name
            small: true
        }

        Callout {
            Layout.fillWidth: true
            visible: WeatherState.stale || (!WeatherState.has_data && !WeatherState.loading && WeatherState.error !== "")
            label: WeatherState.stale ? "Stale data" : "Error"
            value: WeatherState.error || ""
            value_color: Theme.warning
            small: true
        }
    }
}
