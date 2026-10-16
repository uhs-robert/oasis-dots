import QtQuick
import QtQuick.Layouts
import "../../components/ps2"
import "../../theme"
import "../../services"
import "KeeptabsFormat.js" as Fmt

// The Agents tab as the PS2 Browser's memory card screen: the selected session's save-info block over a field of
// save cubes on the tower haze, four across. Same contract as AgentsView.qml.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    readonly property int columns: 4
    readonly property bool moves_across: true
    readonly property bool is_open: Popups.open_name === "keeptabs" && root.visible
    readonly property var current: root.sessions[root.selected] ?? null
    readonly property bool has_context: root.current !== null && root.current.context_pct !== null && root.current.context_pct !== undefined
    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })

    // h/l step one cell, j/k one row. A row step off the end keeps the column: past the last row it wraps to the top
    // row, and from above a short last row it clamps to the last session (up from the top row lands on the last
    // session in that column).
    function nav_target(i, dx, dy) {
        const n = root.sessions.length;
        const cols = root.columns;
        if (n === 0) return 0;
        if (dx !== 0) return ((i + dx) % n + n) % n;
        if (dy > 0) {
            if (i + cols < n) return i + cols;
            return Math.floor(i / cols) === Math.floor((n - 1) / cols) ? i % cols : n - 1;
        }
        if (i >= cols) return i - cols;
        const last_row_start = Math.floor((n - 1) / cols) * cols;
        return last_row_start + i < n ? last_row_start + i : last_row_start - cols + i;
    }

    function ensure_visible(i) {
        cube_grid.positionViewAtIndex(i, GridView.Contain);
    }

    // Token counts read as save sizes: 142k becomes 142 KB.
    function size_text(n) {
        return Fmt.fmt_tokens(n).replace(/k$/, " KB").replace(/M$/, " MB");
    }

    Text {
        anchors.centerIn: parent
        visible: root.sessions.length === 0
        text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    FontMetrics {
        id: title_metrics
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-1)
    }

    Item {
        id: info
        visible: root.current !== null
        width: parent.width - 4
        height: info_col.implicitHeight + 16

        Block {
            anchors.fill: parent
            selected: true
        }

        ColumnLayout {
            id: info_col
            anchors.fill: parent
            anchors.margins: 8
            spacing: 3

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                // Two lines are always reserved so the grid below never shifts between sessions.
                Layout.preferredHeight: title_metrics.lineSpacing * 2
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: root.current ? (root.current.title || "Untitled") : ""
                color: Theme.fg_strong
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-1)
                font.weight: Font.Light
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.current ? (root.current.state || "idle").toUpperCase() + " · " + Fmt.age(root.current.since) : ""
                color: root.current ? Fmt.state_color(root.current.state, root.colors) : Theme.theme_primary_light
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-4)
                font.letterSpacing: 1
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideMiddle
                text: root.current ? (root.current.agent || "claude") + " · " + (root.current.project || "") + " · " + (root.current.where || "") : ""
                color: Theme.theme_primary_light
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-4)
                font.letterSpacing: 1
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: !root.has_context ? "No size data" : root.size_text(root.current.context_used) + " / " + root.size_text(root.current.context_window) + "   " + root.current.context_pct + "%"
                color: Theme.theme_primary_light
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-3)
                font.weight: Font.Light
            }

            GlowBar {
                Layout.fillWidth: true
                value: root.has_context ? root.current.context_pct / 100 : 0
                color: root.has_context ? Fmt.context_bar_color(root.current.context_pct, root.colors) : Theme.theme_primary_light
            }
        }
    }

    Item {
        id: field
        visible: root.sessions.length > 0
        anchors.top: info.bottom
        anchors.topMargin: 8
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true

        Haze {
            anchors.fill: parent
            horizon: 0.8
            towers: 9
            strength: 0.7
        }

        GridView {
            id: cube_grid
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.sessions
            currentIndex: root.selected
            cellWidth: Math.floor(width / root.columns)
            // Exactly two rows fit; more scroll.
            cellHeight: Math.floor(height / 2)

            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool is_selected: cell.index === root.selected
                readonly property string sess_state: cell.modelData.state || "idle"
                readonly property real cube_size: Math.min(GridView.view.cellWidth * 0.5, GridView.view.cellHeight * 0.5)

                width: GridView.view.cellWidth
                height: GridView.view.cellHeight

                Item {
                    id: bobber
                    width: parent.width
                    height: parent.height

                    SequentialAnimation on y {
                        running: root.is_open && cell.sess_state === "waiting"
                        loops: Animation.Infinite
                        NumberAnimation { to: -5; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 700; easing.type: Easing.InOutSine }
                        onRunningChanged: if (!running) bobber.y = 0
                    }

                    SaveCube {
                        id: cube
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.round((parent.height - cube.height) / 2) - 6
                        width: cell.cube_size
                        letter: (cell.modelData.project || cell.modelData.title || "?").charAt(0)
                        color: Fmt.state_color(cell.modelData.state, root.colors)
                        selected: cell.is_selected
                        opacity: cell.sess_state === "idle" ? 0.45 : cell.sess_state === "running" ? 0.8 : 1

                        transform: Rotation {
                            id: turn
                            origin.x: cube.width / 2
                            origin.y: cube.height / 2
                            axis { x: 0; y: 1; z: 0 }

                            SequentialAnimation on angle {
                                running: root.is_open && cell.is_selected
                                loops: Animation.Infinite
                                NumberAnimation { to: 28; duration: 2600; easing.type: Easing.InOutSine }
                                NumberAnimation { to: -28; duration: 5200; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 0; duration: 2600; easing.type: Easing.InOutSine }
                                onRunningChanged: if (!running) turn.angle = 0
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: cube.bottom
                        anchors.topMargin: 8
                        text: Fmt.age(cell.modelData.since)
                        color: cell.is_selected ? Theme.fg_strong : Theme.theme_primary_light
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-5)
                        font.letterSpacing: 1.2
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.on_select(cell.index);
                        root.on_activate(cell.modelData.id);
                    }
                }
            }
        }
    }
}
