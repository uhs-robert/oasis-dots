// home/quickshell/.config/quickshell/components/StatusStrip.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../theme"
import "../services"

// A system status line: nominal or strained, then CPU, volume and weather readouts from services already running.
Rectangle {
    id: root

    property var st: Style.for_item(root)
    readonly property bool strained: SysStats.cpu_percent >= 90 || SysStats.has_temp && SysStats.temp_c >= 80
    readonly property color state_color: root.strained ? Theme.theme_label : Theme.ok
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var readouts: [
        ["CPU", SysStats.cpu_percent + "%"],
        ["VOL", root.sink && root.sink.audio ? (root.sink.audio.muted ? "MUTE" : Math.round(root.sink.audio.volume * 100) + "%") : "--"],
        ["WX", WeatherState.has_data ? Math.round(WeatherState.current.temp) + "°" + WeatherState.unit_symbol() : "--"]
    ]

    implicitHeight: strip.implicitHeight + 8
    color: Qt.alpha(root.state_color, 0.06)

    PwObjectTracker {
        objects: [root.sink].filter(o => o)
    }

    Rectangle {
        width: parent.width
        height: 1
        color: root.st.frame_line
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: root.st.frame_line
    }

    RowLayout {
        id: strip
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        Rectangle {
            Layout.preferredWidth: 6
            Layout.preferredHeight: 6
            rotation: 45
            color: root.state_color
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: root.strained ? "SYS STRAIN" : "SYS NOMINAL"
            color: root.state_color
            font.family: root.st.mono_font
            font.pixelSize: root.st.font_size - 4
            font.letterSpacing: 1.2
        }

        Repeater {
            model: root.readouts

            Row {
                id: readout
                required property var modelData
                spacing: 4

                Text {
                    text: readout.modelData[0]
                    color: root.st.text_muted
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.font_size - 4
                }

                Text {
                    text: readout.modelData[1]
                    color: root.st.text_fg
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.font_size - 4
                }
            }
        }
    }
}
