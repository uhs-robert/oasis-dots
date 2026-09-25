// home/quickshell/.config/quickshell/popups/snes/SnesSoundTest.qml
import QtQuick
import "../../theme"

// A SNES sound-test readout: the track number beside slanted spectrum columns that light up to the played fraction; nothing moves.
Item {
    id: root

    property real ratio: 0
    property string track: ""
    property int column_count: 32
    readonly property real slant: 0.35
    readonly property int gap: 2
    readonly property real track_x: columns.x
    readonly property real track_width: columns.width

    implicitHeight: 30

    Column {
        id: number_box
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
            text: "TRACK"
            color: Theme.theme_primary_light
            style: Text.Raised
            styleColor: Style.text_shadow
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 8
        }

        Text {
            text: root.track !== "" ? root.track.padStart(2, "0") : "--"
            color: Theme.fg_strong
            style: Text.Raised
            styleColor: Style.text_shadow
            font.family: Style.number_font
            font.pixelSize: Style.font_size
        }
    }

    Item {
        id: columns
        x: number_box.width + 10
        width: root.width - x
        height: root.height
        readonly property real lean: root.slant * height
        readonly property real column_width: Math.max(2, (width - lean - root.gap * (root.column_count - 1)) / root.column_count)

        Repeater {
            model: root.column_count

            Rectangle {
                id: column
                required property int index
                readonly property real level: 0.3 + 0.7 * Math.abs(Math.sin(column.index * 1.7) * Math.cos(column.index * 0.6 + 0.4))
                readonly property bool lit: column.index < Math.round(root.ratio * root.column_count)

                x: column.index * (columns.column_width + root.gap)
                y: columns.height - height
                width: columns.column_width
                height: Math.max(3, Math.round(columns.height * column.level))
                antialiasing: true
                transform: Matrix4x4 {
                    matrix: Qt.matrix4x4(1, -root.slant, 0, root.slant * column.height, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }
                gradient: Gradient {
                    GradientStop { position: 0; color: column.lit ? Theme.theme_secondary : Qt.alpha(Theme.theme_primary_light, 0.18) }
                    GradientStop { position: 1; color: column.lit ? Theme.theme_primary_strong : Qt.alpha(Theme.theme_primary_strong, 0.25) }
                }
            }
        }
    }
}
