// home/quickshell/.config/quickshell/popups/battery/LevelRow.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../components/modern" as Modern

// A backlight level row: a capsule slider or a menu row with a plain slider and percent readout.
Item {
    id: root

    property var st: null
    property string glyph: ""
    property string label: ""
    property int percent: 0
    property bool selected: false
    property real percent_width: 32
    property bool capsule: false
    property int floor: 0
    property real top_gap: 0

    signal moved(int pct)
    signal wheeled(var event)

    Layout.fillWidth: true
    Layout.topMargin: root.top_gap
    Layout.preferredHeight: root.capsule ? capsule_loader.implicitHeight : Style.px(22)
    implicitHeight: root.capsule ? capsule_loader.implicitHeight : Style.px(22)

    Loader {
        id: capsule_loader
        active: root.capsule
        visible: active
        anchors.left: parent.left
        anchors.right: parent.right
        sourceComponent: Modern.CapsuleSlider {
            glow: true
            glyph: root.glyph
            label: root.label
            value: root.percent / 100
            selected: root.selected
            onMoved: v => root.moved(Math.max(root.floor, Math.round(v * 100)))

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    root.wheeled(event);
                    event.accepted = true;
                }
            }
        }
    }

    MenuRow {
        id: row
        visible: !root.capsule
        anchors.fill: parent
        selected: root.selected

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                root.wheeled(event);
                event.accepted = true;
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6 + row.inset
            anchors.rightMargin: 6 + row.key_space
            spacing: 8

            Text {
                text: root.glyph
                color: row.fg(root.st.text_primary)
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size
            }

            Slider {
                Layout.fillWidth: true
                on_selection: root.selected
                value: root.percent / 100
                onMoved: v => root.moved(Math.max(root.floor, Math.round(v * 100)))
            }

            Text {
                Layout.preferredWidth: root.percent_width
                text: root.percent + "%"
                color: row.fg(root.st.text_fg)
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-1)
            }
        }
    }
}
