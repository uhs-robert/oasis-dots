// home/quickshell/.config/quickshell/popups/weather/ScanDayColumn.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"

// One day as a Scan Visor readout: a hologram condition icon, the temperature range as a stack of Samus's
// energy tanks on the week's scale, and the rain chance as the missile counter.
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

    readonly property bool has: !!root.day && root.day.max !== undefined
    readonly property int pop: root.has ? Math.round(root.day.pop || 0) : 0
    readonly property color visor: Style.pal.primary
    readonly property color visor_light: Style.pal.primary_light
    readonly property real inner_w: Math.max(10, root.width - 8)

    function frac(v) {
        return Math.max(0, Math.min(1, (v - root.scale_min) / Math.max(0.01, root.scale_max - root.scale_min)));
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(root.visor, root.selected ? 0.07 : 0.025)
    }

    ScanLock {
        shown: root.selected && root.visible && Popups.open_name === "weather"
        visible: root.selected
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        anchors.topMargin: 8
        anchors.bottomMargin: 6
        spacing: 3
        opacity: root.selected ? 1 : 0.62

        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }
        }

        Item {
            id: holo
            readonly property real size: Math.max(18, Math.min(40, root.inner_w - 12))
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: size
            Layout.preferredHeight: size
            clip: true

            WeatherIcon {
                id: holo_icon
                anchors.fill: parent
                size: holo.size
                code: root.has ? root.day.code : 0
                opacity: 0.9
            }

            // A short flicker every few seconds and one scanline sweeping the selected day's hologram.
            SequentialAnimation {
                running: root.selected && root.visible
                loops: Animation.Infinite
                onRunningChanged: if (!running) holo_icon.opacity = 0.9

                PauseAnimation { duration: 2600 }
                NumberAnimation { target: holo_icon; property: "opacity"; to: 0.55; duration: 50 }
                NumberAnimation { target: holo_icon; property: "opacity"; to: 0.9; duration: 70 }
                NumberAnimation { target: holo_icon; property: "opacity"; to: 0.7; duration: 40 }
                NumberAnimation { target: holo_icon; property: "opacity"; to: 0.9; duration: 90 }
            }

            Rectangle {
                visible: root.selected
                width: parent.width
                height: 1
                color: Qt.alpha(root.visor_light, 0.55)

                NumberAnimation on y {
                    running: root.selected && root.visible
                    loops: Animation.Infinite
                    from: 0
                    to: holo.size
                    duration: 1800
                }
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.has ? Math.round(root.day.max) + "°" : ""
            color: Style.pal.fg_strong
            font.family: Style.number_font
            font.pixelSize: Style.fs(-2)
        }

        Item {
            id: tank_area
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 30

            readonly property real gap: 3
            readonly property int count: Math.max(4, Math.min(14, Math.floor((height + gap) / 15)))
            readonly property real step: (height + gap) / count
            readonly property real tank_size: Math.max(5, Math.min(18, root.inner_w * 0.4, step - gap))
            readonly property int first_lit: root.has ? Math.min(count - 1, Math.floor(root.frac(root.day.min) * count)) : count
            // At least the low's own tank stays lit, so a day with no spread still shows where it sits.
            readonly property int last_lit: root.has ? Math.max(first_lit, Math.min(count - 1, Math.ceil(root.frac(root.day.max) * count) - 1)) : -1

            Repeater {
                model: tank_area.count

                Rectangle {
                    required property int index
                    readonly property bool lit: index >= tank_area.first_lit && index <= tank_area.last_lit

                    width: tank_area.tank_size
                    height: tank_area.tank_size
                    x: (tank_area.width - width) / 2
                    y: tank_area.height - index * tank_area.step - tank_area.step / 2 - height / 2 + tank_area.gap / 2
                    radius: Math.min(3, width / 4)
                    color: lit ? (root.selected ? root.visor_light : root.visor) : "transparent"
                    border.width: 1
                    border.color: lit ? Qt.alpha(root.visor_light, 0.9) : Qt.alpha(root.visor, 0.3)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.has ? Math.round(root.day.min) + "°" : ""
            color: Style.text_muted
            font.family: Style.number_font
            font.pixelSize: Style.fs(-3)
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 2
            color: Qt.alpha(root.visor, 0.3)
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 3

            Item {
                id: missile
                anchors.verticalCenter: parent.verticalCenter
                width: 13
                height: 6
                readonly property color tone: root.pop > 0 ? root.visor_light : Qt.alpha(root.visor, 0.4)

                Rectangle {
                    x: 2
                    y: 1
                    width: 8
                    height: 4
                    color: missile.tone
                }

                Rectangle {
                    width: 3
                    height: 6
                    color: missile.tone
                }

                Rectangle {
                    x: 8
                    y: 1
                    width: 4
                    height: 4
                    rotation: 45
                    color: missile.tone
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Zero-padded to three digits like the missile counter.
                text: String(root.pop).padStart(3, "0")
                color: root.pop > 0 ? Style.pal.fg_strong : Style.text_muted
                font.family: Style.number_font
                font.pixelSize: Style.fs(-4)
            }
        }

        SegBar {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Layout.preferredHeight: 3
            count: 5
            gap: 2
            last_lit: Math.ceil(root.pop / 20) - 1
            on_color: root.visor_light
            off_color: Qt.alpha(root.visor, 0.18)
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 3
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.label.toUpperCase()
            color: root.selected ? root.visor_light : root.visor
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
            font.letterSpacing: root.inner_w >= 50 ? 1.5 : 0
        }
    }
}
