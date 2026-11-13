import QtQuick
import QtQuick.Shapes
import qs.theme
import "../BarModules.js" as BarModules
import "../BarLayout.js" as BarLayout
import qs.features.bar
import qs.features.popups

// One lualine section of bar modules: a fill, an arrow in from the previous section, thin separators between components.
// Hovered components light up as powerline segments, like the buffers.
// In a column (`vertical`) the components stack downward and stay upright; the fills, arrows and separators are drawn
// as on a row and turned (`turn`), so `along` and `thick` name the row's width and height.
Item {
    id: root

    property var entries: []
    // Called with (item, entry) once a module loads.
    property var wire: null
    property var module_props: ({})
    property color fill: Style.bar_side_bg
    property color hover_fill: Qt.tint(root.fill, Qt.alpha(Theme.ui_visual_bg, 0.75))
    // The previous section's fill behind the lead arrow; transparent draws none.
    property color lead_bg: "transparent"
    property bool separators: true
    // A strong fill: modules with an `on_accent` property draw in ink colors on it.
    property bool accent: false
    // Set on the island's first section: its first component's fill goes to LualineState for the island cap.
    property string screen_name: ""
    property bool vertical: false
    // Across the bar. The caller can give it from the bar, so it never reads the size it sets.
    property real thick: root.vertical ? root.width : root.height
    readonly property real along: root.vertical ? root.height : root.width
    readonly property int lead_width: BarLayout.lualine_arrow(root.thick) + 1

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
    readonly property real arrow: root.lead_bg.a > 0 ? BarLayout.lualine_arrow(root.thick) : 0
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
    implicitWidth: root.vertical ? 0 : root.arrow + Math.ceil(row.implicitWidth)
    implicitHeight: root.vertical ? root.arrow + Math.ceil(row.implicitHeight) : 0

    // Swaps x and y: every fill is symmetric across the bar, so a swap turns it the same as a quarter turn would.
    Matrix4x4 {
        id: turn
        matrix: Qt.matrix4x4(0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    }

    Shape {
        visible: root.arrow > 0
        width: root.arrow + 1
        height: root.thick
        transform: root.vertical ? [turn] : []
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Style.islands_translucent ? "transparent" : root.lead_bg
            PathRectangle { width: root.arrow; height: root.thick }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Style.islands_translucent ? "transparent" : root.first_lit ? root.hover_fill : root.fill
            PathPolyline {
                path: [Qt.point(root.arrow, 0), Qt.point(root.arrow + 1, 0), Qt.point(root.arrow + 1, root.thick), Qt.point(root.arrow, root.thick), Qt.point(0, root.thick / 2), Qt.point(root.arrow, 0)]
            }
        }

        // Translucent fills must not stack, so the previous section's colour goes beside the arrow rather than under it,
        // and the arrow stops where the first component's fill begins.
        ShapePath {
            strokeWidth: -1
            fillColor: Style.islands_translucent ? Style.island_fill(root.lead_bg) : "transparent"
            PathPolyline {
                path: [Qt.point(0, 0), Qt.point(root.arrow, 0), Qt.point(0, root.thick / 2), Qt.point(root.arrow, root.thick), Qt.point(0, root.thick), Qt.point(0, 0)]
            }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Style.islands_translucent ? Style.island_fill(root.first_lit ? root.hover_fill : root.fill) : "transparent"
            PathPolyline {
                path: [Qt.point(root.arrow, 0), Qt.point(root.arrow, root.thick), Qt.point(0, root.thick / 2), Qt.point(root.arrow, 0)]
            }
        }
    }

    // Translucent, each component fills its own part instead (cells below), so a lit one does not stack on this, and
    // this keeps only the sliver the rounded-up width leaves after them.
    // A turned item's x and y are in the section's own frame, so the offset goes on a child of the turned one.
    Item {
        width: root.along
        height: root.thick
        transform: root.vertical ? [turn] : []

        Rectangle {
            x: root.arrow + (Style.islands_translucent ? (root.vertical ? row.height : row.width) : 0)
            width: root.along - x
            height: root.thick
            color: Style.island_fill(root.fill)
        }
    }

    Grid {
        id: row
        x: root.vertical ? 0 : root.arrow
        y: root.vertical ? root.arrow : 0
        width: root.vertical ? root.width : undefined
        height: root.vertical ? undefined : root.height
        // Only the column count changes with the orientation, so a flip never passes through a grid too small.
        columns: root.vertical ? 1 : Math.max(1, cells.count)

        Repeater {
            id: cells
            model: root.entries

            Grid {
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
                width: root.vertical ? root.width : undefined
                height: root.vertical ? undefined : root.height
                columns: root.vertical ? 1 : 2

                onLitChanged: cell.sync()
                onFirstChanged: cell.sync()
                onLastChanged: cell.sync()
                // A click anywhere in the cell, lead and padding included, opens the module's popup.
                function activate() {
                    const it = loader.item;
                    if (!it || !it.island || !BarModules.has_popup(cell.modelData.base)) return;
                    // Through the module's helper where it has one, so a click on a hover-open popup pins it.
                    if (it.toggle_popup) it.toggle_popup();
                    else if (it.click_popup) it.click_popup();
                    else Popups.toggle(cell.modelData.base, it.island, it.island_color, it.screen_name || "");
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
                    width: root.vertical ? root.width : root.lead_width
                    height: root.vertical ? root.lead_width : root.height

                    MouseArea {
                        anchors.fill: parent
                        onClicked: cell.activate()
                    }

                    // Translucent: this gap's own fill, under the separator. A Rectangle where both sides match, since
                    // a Shape's antialiased edge at a fractional x would show against the cells' fills.
                    Rectangle {
                        visible: Style.islands_translucent && cell.lit === cell.prev_lit
                        z: -1
                        anchors.fill: parent
                        color: Style.island_fill(cell.lit ? root.hover_fill : root.fill)
                    }

                    // The separator and arrows as on a row, turned in a column.
                    Item {
                        width: root.lead_width
                        height: root.thick
                        transform: root.vertical ? [turn] : []

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

                        // Translucent where the sides differ: the component before's colour beside this one's arrow.
                        Shape {
                            visible: Style.islands_translucent && cell.lit !== cell.prev_lit
                            z: -1
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeWidth: -1
                                fillColor: Style.island_fill(cell.prev_lit ? root.hover_fill : root.fill)
                                PathPolyline {
                                    path: [Qt.point(0, 0), Qt.point(root.lead_width, 0), Qt.point(0, root.thick / 2), Qt.point(root.lead_width, root.thick), Qt.point(0, root.thick), Qt.point(0, 0)]
                                }
                            }

                            ShapePath {
                                strokeWidth: -1
                                fillColor: Style.island_fill(cell.lit ? root.hover_fill : root.fill)
                                PathPolyline {
                                    path: [Qt.point(root.lead_width, 0), Qt.point(root.lead_width, root.thick), Qt.point(0, root.thick / 2), Qt.point(root.lead_width, 0)]
                                }
                            }
                        }

                        // Right-side lualine arrows point left: this component's fill over the one before it.
                        Shape {
                            visible: cell.lit !== cell.prev_lit && !Style.islands_translucent
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeWidth: -1
                                fillColor: cell.prev_lit ? root.hover_fill : root.fill
                                PathRectangle { width: root.lead_width; height: root.thick }
                            }

                            ShapePath {
                                strokeWidth: -1
                                fillColor: cell.lit ? root.hover_fill : root.fill
                                PathPolyline {
                                    path: [Qt.point(root.lead_width - 1, 0), Qt.point(root.lead_width, 0), Qt.point(root.lead_width, root.thick), Qt.point(root.lead_width - 1, root.thick), Qt.point(0, root.thick / 2), Qt.point(root.lead_width - 1, 0)]
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: root.vertical ? root.width : loader.implicitWidth + pad_left + pad_right
                    height: root.vertical ? loader.implicitHeight + pad_left + pad_right : root.height
                    color: cell.lit ? Style.island_fill(root.hover_fill) : Style.islands_translucent ? Style.island_fill(root.fill) : "transparent"
                    readonly property int pad_left: cell.first ? 10 : 4
                    readonly property int pad_right: cell.last ? 10 : 5

                    // Under the module, so its own MouseAreas still take clicks on it.
                    MouseArea {
                        anchors.fill: parent
                        onClicked: cell.activate()
                    }

                    Loader {
                        id: loader
                        // pad_left in along the bar, centred across it. The anchor stays set in a column and the offset
                        // moves it to pad_left: an anchor dropped when the bar turns would leave the module where it was.
                        x: root.vertical ? Math.round((parent.width - implicitWidth) / 2) : parent.pad_left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: root.vertical ? parent.pad_left + height / 2 - parent.height / 2 : 0
                        Component.onCompleted: setSource(cell.modelData.url, Object.assign({ compact: cell.modelData.compact }, root.module_props))
                        onLoaded: {
                            if (item.hasOwnProperty("on_accent")) item.on_accent = Qt.binding(() => root.accent);
                            // The whole cell is the module's hover zone, so the lead arrow and padding open the popup too.
                            if (item.hasOwnProperty("cell_hovered")) item.cell_hovered = Qt.binding(() => cell_hover.hovered);
                            if (root.wire) root.wire(item, cell.modelData);
                        }
                    }
                }
            }
        }
    }
}
