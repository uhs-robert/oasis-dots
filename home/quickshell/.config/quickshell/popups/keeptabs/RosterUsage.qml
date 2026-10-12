// home/quickshell/.config/quickshell/popups/keeptabs/RosterUsage.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../theme"
import "../../services"
import "KeeptabsFormat.js" as Fmt

// The Reticle Usage tab: the limits as concentric rings, the first row outermost, each with a leader line
// out to a callout carrying its label, percent and reset time. Contract as in UsageView.qml.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })
    // Other styles leave the hairline tokens transparent, so borrowed rings fall back to the palette.
    readonly property color hairline: root.st.hairline.a > 0 ? root.st.hairline : Qt.alpha(Style.pal.fg_strong, 0.55)
    readonly property color hairline_dim: root.st.hairline_dim.a > 0 ? root.st.hairline_dim : Qt.alpha(Style.pal.fg_strong, 0.24)

    readonly property var rows: ClaudeUsageState.rows
    readonly property int count: root.rows.length
    readonly property real outer_radius: 64
    readonly property real ring_width: 4
    // Closer rings when there are many, so the innermost still leaves room for the readout.
    readonly property real ring_step: root.count > 1 ? Math.min(13, (root.outer_radius - 24) / (root.count - 1)) : 0
    readonly property real cluster_size: 2 * root.outer_radius + 8
    readonly property real cell_height: root.count > 0 ? Math.min(46, area.height / root.count) : 46
    readonly property real callout_x: root.cluster_size + 26

    function ring_radius(i) {
        return root.outer_radius - i * root.ring_step;
    }

    function clamp_fraction(percent) {
        return Math.max(0, Math.min(1, percent / 100));
    }

    // The leader leaves each ring on its upper right, at an angle that spreads the anchors, and runs level into its callout.
    function leader_points(i, cx, cy) {
        const a = (70 - 50 * (root.count > 1 ? i / (root.count - 1) : 0)) * Math.PI / 180;
        const r = root.ring_radius(i);
        const y = cy + (i - (root.count - 1) / 2) * root.cell_height;
        return [Qt.point(cx + r * Math.cos(a), cy - r * Math.sin(a)), Qt.point(root.cluster_size + 10, y), Qt.point(root.callout_x - 4, y)];
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: ClaudeUsageState.loading ? "Loading…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "Claude usage")
            color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Style.pal.warning : root.st.text_muted
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-4)
            font.bold: true
            font.letterSpacing: 2.5
            font.capitalization: Font.AllUppercase
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 24
            visible: root.count === 0 && !ClaudeUsageState.loading
            text: ClaudeUsageState.error ? "" : "No usage data yet"
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-1)
        }

        Item {
            id: area
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.count > 0

            readonly property real cx: 4 + root.outer_radius + 4
            readonly property real cy: area.height / 2

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                // Each layer is its own Repeater of ShapePaths: a Shape draws only paths that are its direct children.
                Repeater {
                    model: root.rows

                    ShapePath {
                        id: track
                        required property int index
                        strokeWidth: root.ring_width
                        strokeColor: Qt.alpha(root.st.text_strong, 0.12)
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        PathAngleArc { centerX: area.cx; centerY: area.cy; radiusX: root.ring_radius(track.index); radiusY: root.ring_radius(track.index); startAngle: 0; sweepAngle: 360 }
                    }
                }

                Repeater {
                    model: root.rows

                    ShapePath {
                        id: lit
                        required property var modelData
                        required property int index
                        strokeWidth: lit.modelData.percent > 0 ? root.ring_width : -1
                        strokeColor: Fmt.context_bar_color(lit.modelData.percent, root.colors)
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        PathAngleArc {
                            centerX: area.cx
                            centerY: area.cy
                            radiusX: root.ring_radius(lit.index)
                            radiusY: root.ring_radius(lit.index)
                            startAngle: -90
                            sweepAngle: 360 * root.clamp_fraction(lit.modelData.percent)
                        }
                    }
                }

                Repeater {
                    model: root.rows

                    ShapePath {
                        id: leader
                        required property int index
                        strokeWidth: 1
                        strokeColor: root.hairline
                        fillColor: "transparent"
                        PathPolyline { path: root.leader_points(leader.index, area.cx, area.cy) }
                    }
                }
            }

            // The first limit's percent in the middle, where the rings leave room.
            Text {
                x: area.cx - width / 2
                y: area.cy - height / 2
                text: root.count > 0 ? root.rows[0].percent + "%" : ""
                color: root.st.text_strong
                font.family: root.st.number_font
                font.weight: Font.ExtraLight
                font.pixelSize: root.st.fs(4)
            }

            Repeater {
                model: root.rows

                ColumnLayout {
                    id: callout
                    required property var modelData
                    required property int index

                    x: root.callout_x
                    y: area.cy + (callout.index - (root.count - 1) / 2) * root.cell_height - callout.height / 2
                    width: area.width - root.callout_x
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: callout.modelData.label
                            color: root.st.text_muted
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-5)
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 2
                        }

                        Text {
                            text: callout.modelData.percent + "%"
                            color: Fmt.context_bar_color(callout.modelData.percent, root.colors)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-1)
                            font.bold: true
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: callout.modelData.resets !== ""
                        text: "resets " + callout.modelData.resets
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }
                }
            }
        }
    }
}
