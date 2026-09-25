// home/quickshell/.config/quickshell/components/neovim/LualineSection.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"
import "../../services"

// One lualine section of bar modules: a fill, an arrow in from the previous section, thin separators between components.
// Hovered components light up as powerline segments, like the buffers.
Item {
    id: root

    property var entries: []
    // Called with (item, entry) once a module loads.
    property var wire: null
    property color fill: Style.bar_side_bg
    property color hover_fill: Qt.tint(root.fill, Qt.alpha(Theme.ui_visual_bg, 0.75))
    // The previous section's fill behind the lead arrow; transparent draws none.
    property color lead_bg: "transparent"
    property bool separators: true
    // A strong fill: modules with an `on_accent` property draw in ink colors on it.
    property bool accent: false
    // Set on the island's first section: its first component's fill goes to LualineState for the island cap.
    property string screen_name: ""
    readonly property int lead_width: Math.round(root.height * 0.4) + 1

    readonly property int first_shown: {
        for (let i = 0; i < cells.count; i++) {
            const cell = cells.itemAt(i);
            if (cell && cell.wanted) return i;
        }
        return -1;
    }
    readonly property int last_shown: {
        for (let i = cells.count - 1; i >= 0; i--) {
            const cell = cells.itemAt(i);
            if (cell && cell.wanted) return i;
        }
        return -1;
    }
    readonly property bool shown: root.first_shown >= 0
    readonly property real arrow: root.lead_bg.a > 0 ? Math.round(root.height * 0.4) : 0
    // Pushed by the end cells themselves, like the buffers do; bindings through itemAt() missed hover changes.
    property bool first_lit: false
    property bool last_lit: false
    // What the next section's arrow sits on.
    readonly property color end_fill: root.last_lit ? root.hover_fill : root.fill

    onFirst_litChanged: root.publish()
    Component.onCompleted: root.publish()
    function publish() {
        if (root.screen_name !== "") LualineState.set_right_first_fill(root.screen_name, root.first_lit ? root.hover_fill : Qt.rgba(0, 0, 0, 0));
    }

    visible: root.shown
    implicitWidth: root.arrow + Math.ceil(row.implicitWidth)

    Shape {
        visible: root.arrow > 0
        width: root.arrow + 1
        height: root.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.lead_bg
            PathRectangle { width: root.arrow; height: root.height }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: root.first_lit ? root.hover_fill : root.fill
            PathPolyline {
                path: [Qt.point(root.arrow, 0), Qt.point(root.arrow + 1, 0), Qt.point(root.arrow + 1, root.height), Qt.point(root.arrow, root.height), Qt.point(0, root.height / 2), Qt.point(root.arrow, 0)]
            }
        }
    }

    Rectangle {
        x: root.arrow
        width: root.width - root.arrow
        height: root.height
        color: root.fill
    }

    Row {
        id: row
        x: root.arrow
        height: root.height

        Repeater {
            id: cells
            model: root.entries

            Row {
                id: cell
                required property var modelData
                required property int index
                // A module's own `shown`, not `visible`: a hidden section would report every child hidden.
                readonly property bool wanted: !loader.item || loader.item.shown === undefined || loader.item.shown
                readonly property bool first: cell.index === root.first_shown
                readonly property bool last: cell.index === root.last_shown
                // Its module's popup is open on this screen, by click, key or IPC.
                readonly property bool popup_open: !!loader.item && Popups.open_name === cell.modelData.base && Popups.open_screen_name === (loader.item.screen_name || "")
                readonly property bool lit: cell_hover.hovered || cell.popup_open
                readonly property bool prev_lit: {
                    for (let i = cell.index - 1; i >= 0; i--) {
                        const c = cells.itemAt(i);
                        if (c && c.wanted) return c.lit;
                    }
                    return false;
                }

                visible: cell.wanted
                height: root.height

                onLitChanged: cell.sync()
                onFirstChanged: cell.sync()
                onLastChanged: cell.sync()
                // A click anywhere in the cell, lead and padding included, opens the module's popup.
                function activate() {
                    const it = loader.item;
                    if (!it || !it.island || cell.modelData.base === "voxtype") return;
                    Popups.toggle(cell.modelData.base, it.island, it.island_color, it.screen_name || "");
                }

                function sync() {
                    if (cell.first) root.first_lit = cell.lit;
                    if (cell.last) root.last_lit = cell.lit;
                }

                HoverHandler {
                    id: cell_hover
                }

                // Fixed width, so lighting a component never shifts the row under the pointer.
                Item {
                    visible: !cell.first
                    width: root.lead_width
                    height: root.height

                    MouseArea {
                        anchors.fill: parent
                        onClicked: cell.activate()
                    }

                    Shape {
                        visible: root.separators && !cell.lit && !cell.prev_lit
                        anchors.centerIn: parent
                        width: 6
                        height: 16
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: 1.2
                            strokeColor: root.accent ? Qt.alpha(Theme.bg_crust, 0.55) : Style.text_muted
                            fillColor: "transparent"
                            startX: 5
                            startY: 1
                            PathLine { x: 1; y: 8 }
                            PathLine { x: 5; y: 15 }
                        }
                    }

                    // Right-side lualine arrows point left: this component's fill over the one before it.
                    Shape {
                        visible: cell.lit !== cell.prev_lit
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: -1
                            fillColor: cell.prev_lit ? root.hover_fill : root.fill
                            PathRectangle { width: root.lead_width; height: root.height }
                        }

                        ShapePath {
                            strokeWidth: -1
                            fillColor: cell.lit ? root.hover_fill : root.fill
                            PathPolyline {
                                path: [Qt.point(root.lead_width - 1, 0), Qt.point(root.lead_width, 0), Qt.point(root.lead_width, root.height), Qt.point(root.lead_width - 1, root.height), Qt.point(0, root.height / 2), Qt.point(root.lead_width - 1, 0)]
                            }
                        }
                    }
                }

                Rectangle {
                    width: loader.implicitWidth + pad_left + pad_right
                    height: root.height
                    color: cell.lit ? root.hover_fill : "transparent"
                    readonly property int pad_left: cell.first ? 10 : 4
                    readonly property int pad_right: cell.last ? 10 : 5

                    // Under the module, so its own MouseAreas still take clicks on it.
                    MouseArea {
                        anchors.fill: parent
                        onClicked: cell.activate()
                    }

                    Loader {
                        id: loader
                        x: parent.pad_left
                        anchors.verticalCenter: parent.verticalCenter
                        sourceComponent: cell.modelData.component
                        onLoaded: {
                            if (item.hasOwnProperty("on_accent")) item.on_accent = Qt.binding(() => root.accent);
                            if (root.wire) root.wire(item, cell.modelData);
                        }
                    }
                }
            }
        }
    }
}
