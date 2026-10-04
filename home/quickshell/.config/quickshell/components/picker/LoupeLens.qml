// home/quickshell/.config/quickshell/components/picker/LoupeLens.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"

// The loupe's magnified view: buffer pixels, zoom grid and centre-pixel box; skin overlays go between them.
Item {
    id: lens

    required property var loupe
    property color grid_color: Qt.alpha(Theme.bg_shadow, 0.35)
    property color center_color: Style.caret_color
    default property alias overlay: overlay_host.data
    readonly property alias center_px: center_px

    width: lens.loupe.view
    height: lens.loupe.view
    clip: true

    ShaderEffectSource {
        anchors.fill: parent
        sourceItem: lens.loupe.source
        sourceRect: Qt.rect((lens.loupe.bx - lens.loupe.half) / lens.loupe.sample_scale, (lens.loupe.by - lens.loupe.half) / lens.loupe.sample_scale, lens.loupe.count / lens.loupe.sample_scale, lens.loupe.count / lens.loupe.sample_scale)
        textureSize: Qt.size(lens.loupe.count, lens.loupe.count)
        smooth: false
        mipmap: false
    }

    Repeater {
        model: lens.loupe.visible && lens.loupe.zoom >= 8 ? lens.loupe.count + 1 : 0

        Item {
            id: grid_line
            required property int index
            anchors.fill: parent

            Rectangle {
                x: grid_line.index * lens.loupe.zoom
                width: 1
                height: parent.height
                color: lens.grid_color
            }

            Rectangle {
                y: grid_line.index * lens.loupe.zoom
                width: parent.width
                height: 1
                color: lens.grid_color
            }
        }
    }

    Item {
        id: overlay_host
        anchors.fill: parent
    }

    Rectangle {
        id: center_px
        x: lens.loupe.half * lens.loupe.zoom - border.width
        y: lens.loupe.half * lens.loupe.zoom - border.width
        width: lens.loupe.zoom + border.width * 2
        height: lens.loupe.zoom + border.width * 2
        color: "transparent"
        border.width: lens.loupe.zoom >= 8 ? 2 : 1
        border.color: lens.center_color
    }
}
