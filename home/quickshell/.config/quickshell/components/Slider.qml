// home/quickshell/.config/quickshell/components/Slider.qml
import QtQuick
import "../theme"

Item {
    id: root

    readonly property var st: Style.for_item(root)

    property real value: 0
    property bool on_selection: false
    signal moved(real value)

    implicitHeight: Style.px(14)

    function set_from_x(x) {
        const span = root.st.segmented_levels && root.st.slider_readout ? root.width - readout.width - 6 : track.width;
        root.moved(Math.max(0, Math.min(1, x / Math.max(1, span))));
    }

    Rectangle {
        id: track
        visible: !root.st.segmented_levels
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        radius: Style.radius(3)
        color: Theme.bg_surface

        Rectangle {
            width: track.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            radius: parent.radius
            color: root.on_selection && root.st.selection_inverse ? root.st.selection_fg : Theme.theme_primary
        }
    }

    Meter {
        visible: root.st.segmented_levels
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: root.st.slider_readout ? readout.width + 6 : 0
        anchors.verticalCenter: parent.verticalCenter
        value: root.value
        hot_from: 0.9
        on_selection: root.on_selection
    }

    Text {
        id: readout
        visible: root.st.slider_readout
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.st.slider_readout ? Math.ceil(readout_metrics.advanceWidth("100")) : 0
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.value * 100)
        color: root.on_selection && root.st.selection_inverse ? root.st.selection_fg : root.st.text_strong
        font.family: root.st.mono_font
        font.pixelSize: root.st.font_size - 3
    }

    FontMetrics {
        id: readout_metrics
        font.family: root.st.mono_font
        font.pixelSize: root.st.font_size - 3
    }

    MouseArea {
        anchors.fill: parent
        onPressed: mouse => root.set_from_x(mouse.x)
        onPositionChanged: mouse => {
            if (pressed) root.set_from_x(mouse.x);
        }
    }
}
