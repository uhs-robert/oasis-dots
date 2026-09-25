// home/quickshell/.config/quickshell/components/neovim/BufferLine.qml
import QtQuick
import QtQuick.Shapes
import Quickshell.Hyprland
import "../../theme"
import "../../services"
import ".."

// Workspaces as lualine buffers: number and app icons, the focused one a full-height visual-bg segment with arrow edges.
Item {
    id: root

    // The Workspaces module, for its icon, name and window helpers.
    required property Item host
    property var workspaces: []
    property bool compact: false
    property int bar_height: 30

    readonly property int glyph: root.compact ? 14 : 16
    readonly property int arrow: Math.round(root.bar_height * 0.4)
    readonly property color accent: SubmapState.bar_color

    implicitWidth: row.implicitWidth
    implicitHeight: root.bar_height

    Row {
        id: row
        height: root.height

        Repeater {
            id: slots
            model: root.workspaces

            Row {
                id: slot
                required property var modelData
                required property int index
                readonly property var toplevels: slot.modelData.toplevels.values
                readonly property bool empty: slot.toplevels.length === 0
                readonly property bool focused: slot.modelData.focused
                readonly property bool lit: slot.focused || slot_hover.hovered
                readonly property color lit_fill: slot.focused ? Theme.ui_visual_bg : Qt.tint(Style.bar_side_bg, Qt.alpha(Theme.ui_visual_bg, 0.75))
                readonly property Item prev_slot: slot.index > 0 ? slots.itemAt(slot.index - 1) : null
                readonly property bool is_last: slot.index === root.workspaces.length - 1
                onIs_lastChanged: slot.publish()
                readonly property Item next_slot: slots.count > slot.index + 1 ? slots.itemAt(slot.index + 1) : null
                readonly property bool prev_lit: !!slot.prev_slot && slot.prev_slot.lit
                readonly property color next_fill: !!slot.next_slot && slot.next_slot.lit ? slot.next_slot.lit_fill : "transparent"

                onLit_fillChanged: slot.publish()
                onLitChanged: slot.publish()
                Component.onCompleted: slot.publish()
                function publish() {
                    if (!root.host) return;
                    const fill = slot.lit ? slot.lit_fill : Qt.rgba(0, 0, 0, 0);
                    if (slot.index === 0) LualineState.set_first_fill(root.host.screen_name, fill);
                    if (slot.is_last) LualineState.set_last_fill(root.host.screen_name, fill);
                }

                height: row.height
                z: slot.lit ? 1 : 0

                HoverHandler {
                    id: slot_hover
                }

                // Fixed width, so lighting a buffer never shifts the row under the pointer.
                Item {
                    visible: slot.index > 0
                    width: root.arrow + 1
                    height: slot.height

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = '" + slot.modelData.id + "' })")
                    }

                    Shape {
                        visible: slot.lit && !slot.prev_lit
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: -1
                            fillColor: slot.lit_fill
                            PathPolyline {
                                path: [Qt.point(0, 0), Qt.point(root.arrow + 1, 0), Qt.point(root.arrow + 1, slot.height), Qt.point(0, slot.height), Qt.point(root.arrow, slot.height / 2), Qt.point(0, 0)]
                            }
                        }
                    }
                }

                Rectangle {
                    id: buffer
                    width: content.implicitWidth + 16
                    height: slot.height
                    color: slot.lit ? slot.lit_fill : "transparent"

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = '" + slot.modelData.id + "' })")
                    }

                    Shape {
                        visible: slot.lit && !slot.is_last
                        x: parent.width
                        width: root.arrow + 1
                        height: slot.height
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: -1
                            fillColor: slot.next_fill
                            PathRectangle { width: root.arrow + 1; height: slot.height }
                        }

                        ShapePath {
                            strokeWidth: -1
                            fillColor: slot.lit_fill
                            PathPolyline {
                                path: [Qt.point(-1, 0), Qt.point(0, 0), Qt.point(root.arrow, slot.height / 2), Qt.point(0, slot.height), Qt.point(-1, slot.height), Qt.point(-1, 0)]
                            }
                        }
                    }

                    Row {
                        id: content
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            rightPadding: slot.empty ? 0 : 2
                            text: String(slot.modelData.id)
                            color: slot.focused ? root.accent : slot.modelData.active ? Theme.theme_primary : slot.empty ? Style.text_muted : Style.text_dim
                            font.family: Style.bar_font_family
                            font.pixelSize: Style.bar_font_size
                            font.bold: true
                        }

                        Repeater {
                            model: slot.toplevels

                            WorkspaceIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                host: root.host
                                workspace_id: slot.modelData.id
                                glyph: root.glyph
                                icon_opacity: slot.focused || slot.modelData.active ? 1 : 0.7
                                width: root.glyph + 2
                                height: root.glyph + 2
                            }
                        }
                    }
                }

            }
        }
    }
}
