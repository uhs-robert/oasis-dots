// home/quickshell/.config/quickshell/popups/battery/WatchGauge.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components/goldeneye" as Goldeneye

// The goldeneye battery header: the gauge dial beside status, draw, time, health and profile readouts.
Goldeneye.GaugeHeader {
    id: root

    property real percent: 0
    property string state_label: ""
    property real rate: 0
    property string time_label: ""
    property var device: null
    property bool ppd_available: false
    property string profile_label: ""

    readonly property bool is_low: root.percent <= 20 && root.state_label === "Discharging"

    size: Style.px(100)
    value: root.percent / 100
    low: root.is_low
    label: "BATTERY"

    Goldeneye.ReadoutLine {
        Layout.fillWidth: true
        label: "STATUS"
        alert: root.is_low
        text: root.state_label
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: root.rate > 0 || root.time_label !== ""

        Goldeneye.ReadoutLine {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            visible: root.rate > 0
            label: "DRAW"
            digits: root.rate.toFixed(1)
            unit: "W"
        }

        Goldeneye.ReadoutLine {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            visible: root.time_label !== ""
            label: root.state_label === "Charging" ? "TO FULL" : "LEFT"
            text: root.time_label.replace(" remaining", "").replace(" until full", "")
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: healthy || (root.ppd_available && root.profile_label !== "")
        readonly property bool healthy: !!root.device && root.device.healthSupported

        Goldeneye.ReadoutLine {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            visible: parent.healthy
            label: "HEALTH"
            digits: root.device && root.device.healthSupported ? String(Math.round(root.device.healthPercentage)) : ""
            unit: "%"
        }

        Goldeneye.ReadoutLine {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            visible: root.ppd_available && root.profile_label !== ""
            label: "PROFILE"
            text: root.profile_label
        }
    }
}
