// home/quickshell/.config/quickshell/components/Meter.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "../theme"

Item {
    id: root

    readonly property var st: Style.for_item(root)

    property real value: 0
    property bool hot: false
    // Lit segments from this fraction up take the hot color.
    property real hot_from: 1
    // Set on an inverse-selected row so the lit segments stay visible.
    property bool on_selection: false
    property int segment_count: 20
    // Indeterminate: a short lit run sweeps across instead of showing value.
    property bool busy: false
    property real busy_pos: 0
    readonly property int busy_span: 4
    readonly property int busy_head: Math.floor(root.busy_pos * (root.segment_count + root.busy_span)) - root.busy_span
    property color on_color: root.st.meter_on
    readonly property int gap: 2
    // Slanted segments lean past their slot by this much at the top.
    readonly property real lean: root.st.meter_slant * root.implicitHeight
    readonly property real segment_width: Math.max(2, (width - root.lean - gap * (segment_count - 1)) / segment_count)

    implicitWidth: segment_count * 3 + gap * (segment_count - 1)
    implicitHeight: root.st.meter_height > 0 ? root.st.meter_height : Style.px(10)

    NumberAnimation on busy_pos {
        running: root.busy
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: 1400
    }

    // Rebuilt per style like the popup effects: a blurred copy under the segments.
    Loader {
        anchors.fill: segments
        active: root.st.meter_bloom
        sourceComponent: MultiEffect {
            source: segments
            blurEnabled: true
            blur: 0.4
            blurMax: 8
            brightness: 0.15
        }
    }

    Loader {
        width: root.width
        height: root.implicitHeight
        active: root.st.tick_ruler
        sourceComponent: TickRuler {
            meter: root
        }
    }

    Item {
        id: segments
        visible: !root.st.tick_ruler
        width: root.width
        height: root.implicitHeight
        layer.enabled: root.st.meter_bloom

        Row {
            spacing: root.gap

            Repeater {
                model: root.segment_count

                Rectangle {
                    id: segment
                    required property int index
                    readonly property bool lit: root.busy
                        ? index >= root.busy_head && index < root.busy_head + root.busy_span
                        : index < Math.round(root.value * root.segment_count)
                    readonly property bool is_hot: root.hot || index >= Math.round(root.hot_from * root.segment_count)

                    width: root.segment_width
                    height: root.implicitHeight
                    radius: root.st.meter_radius
                    border.width: root.st.meter_outline.a > 0 ? 1 : 0
                    border.color: segment.lit && segment.is_hot ? root.st.meter_hot : root.st.meter_outline
                    antialiasing: root.st.meter_slant > 0
                    transform: Matrix4x4 {
                        matrix: Qt.matrix4x4(1, -root.st.meter_slant, 0, root.st.meter_slant * segment.height, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                    }
                    color: segment.lit
                        ? (segment.is_hot ? root.st.meter_hot : root.on_selection && root.st.selection_inverse ? root.st.selection_fg : root.on_color)
                        : root.on_selection && root.st.selection_inverse ? Qt.alpha(root.st.selection_fg, 0.25) : root.st.meter_major.a > 0 && index % 5 === 4 ? root.st.meter_major : root.st.meter_off

                    // Lit segments shade down from meter_shade at the top.
                    Rectangle {
                        visible: segment.lit && !segment.is_hot && root.st.meter_shade.a > 0
                        anchors.fill: parent
                        radius: parent.radius
                        gradient: Gradient {
                            GradientStop { position: 0; color: root.st.meter_shade }
                            GradientStop { position: 0.6; color: Qt.alpha(root.st.meter_shade, 0) }
                        }
                    }
                }
            }
        }
    }
}
