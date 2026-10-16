pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.components.metroid
import qs.theme
import qs.services
import qs.popups.weather
import "KeeptabsFormat.js" as Fmt

// The Agents tab as a Scan Visor logbook: sessions are entries in a list with a scan marker each, and the selected
// one opens in the entry panel beside it. Waiting entries are critical (red, pulsing), running ones scan (orange),
// done ones are scanned (blue) and idle ones stay dim. The contract is AgentsView's.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })
    readonly property color visor: Style.pal.primary
    readonly property color visor_light: Style.pal.primary_light
    readonly property bool animating: Popups.open_name === "keeptabs" && root.visible
    readonly property var entry: root.sessions.length > 0 ? root.sessions[Math.max(0, Math.min(root.selected, root.sessions.length - 1))] : null
    readonly property bool entry_has_context: !!root.entry && root.entry.context_pct !== null && root.entry.context_pct !== undefined

    function ensure_visible(i) {
        entry_list.positionViewAtIndex(i, ListView.Contain);
    }

    function marker_color(state) {
        if (state === "waiting") return Style.pal.red;
        if (state === "running") return Style.pal.bright_yellow;
        if (state === "done") return root.visor_light;
        return root.st.text_dim;
    }

    // Names the unit the way a scan log would, skipping whichever parts the session lacks.
    function analysis(s) {
        const agent = s.agent || "claude";
        const where = [s.project, s.where].filter(x => !!x);
        const place = where.length > 0 ? " operating in " + where.join(" · ") : " operating";
        return agent.charAt(0).toUpperCase() + agent.slice(1) + " unit" + place + " · " + Fmt.age(s.since) + " in current state";
    }

    Text {
        anchors.centerIn: parent
        visible: root.sessions.length === 0
        text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    RowLayout {
        anchors.fill: parent
        visible: root.sessions.length > 0
        spacing: 8

        ListView {
            id: entry_list
            Layout.preferredWidth: 120
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.sessions
            currentIndex: root.selected

            delegate: Item {
                id: entry_row
                required property var modelData
                required property int index
                readonly property bool is_selected: entry_row.index === root.selected
                readonly property color tone: root.marker_color(entry_row.modelData.state)

                width: entry_list.width
                height: Style.px(28)

                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(root.visor, entry_row.is_selected ? 0.1 : 0.03)
                }

                ScanLock {
                    shown: entry_row.is_selected && root.animating
                    visible: entry_row.is_selected
                }

                Item {
                    id: marker
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 9
                    clip: true
                    opacity: 1

                    Rectangle {
                        anchors.fill: parent
                        color: entry_row.modelData.state === "idle" ? "transparent" : Qt.alpha(entry_row.tone, entry_row.modelData.state === "done" ? 0.55 : 0.85)
                        border.width: 1
                        border.color: entry_row.tone
                    }

                    // The scan line crossing a running entry's marker.
                    Rectangle {
                        visible: entry_row.modelData.state === "running"
                        width: parent.width
                        height: 2
                        color: Style.pal.fg_strong

                        NumberAnimation on y {
                            running: entry_row.modelData.state === "running" && root.animating
                            loops: Animation.Infinite
                            from: -2
                            to: marker.height
                            duration: 900
                        }
                    }

                    SequentialAnimation on opacity {
                        running: entry_row.modelData.state === "waiting" && root.animating
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) marker.opacity = 1

                        NumberAnimation { to: 0.25; duration: 420 }
                        NumberAnimation { to: 1; duration: 420 }
                    }
                }

                Text {
                    anchors.left: marker.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: entry_row.modelData.title || "Untitled"
                    color: entry_row.is_selected ? Style.pal.fg_strong : root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.on_select(entry_row.index);
                        root.on_activate(entry_row.modelData.id);
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0

            VisorGlass {
                anchors.fill: parent
                visible: true
                top_cut: 4
                border_color: Qt.alpha(root.visor, 0.4)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                anchors.bottomMargin: 14
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: "ENTRY " + String(root.selected + 1).padStart(2, "0") + "/" + String(root.sessions.length).padStart(2, "0")
                        color: root.entry ? root.marker_color(root.entry.state) : root.visor
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                        font.letterSpacing: 2
                    }

                    // Never elided: the state word keeps its full width and the index gives way.
                    Text {
                        text: root.entry ? (root.entry.state || "idle").toUpperCase() : ""
                        color: root.entry ? root.marker_color(root.entry.state) : root.visor
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                        font.letterSpacing: 2
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.entry ? (root.entry.title || "Untitled") : ""
                    color: Style.pal.fg_strong
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-1)
                    font.bold: true
                }

                CompassRule {
                    Layout.fillWidth: true
                    color: Qt.alpha(root.visor, 0.6)
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    lineHeight: 1.1
                    text: root.entry ? root.analysis(root.entry) : ""
                    color: root.st.text_fg
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                }

                Item {
                    Layout.fillHeight: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "CONTEXT"
                        color: root.visor
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                        font.letterSpacing: 2
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.entry_has_context ? root.entry.context_pct + "%" : "--"
                        color: root.entry_has_context ? Fmt.context_bar_color(root.entry.context_pct, root.colors) : root.st.text_dim
                        font.family: Style.number_font
                        font.pixelSize: root.st.fs(-2)
                    }
                }

                // One tank per tenth of the window used, like the energy tanks above Samus's count.
                SegBar {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 7
                    count: 10
                    gap: 3
                    last_lit: root.entry_has_context ? Math.round(root.entry.context_pct / 10) - 1 : -1
                    on_color: root.entry_has_context ? Fmt.context_bar_color(root.entry.context_pct, root.colors) : root.visor
                    off_color: Qt.alpha(root.visor, 0.14)
                }

                SegBar {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                    count: 30
                    gap: 1
                    last_lit: root.entry_has_context ? Math.round(root.entry.context_pct * 0.3) - 1 : -1
                    on_color: root.entry_has_context ? Fmt.context_bar_color(root.entry.context_pct, root.colors) : root.visor
                    off_color: Qt.alpha(root.visor, 0.14)
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.entry_has_context ? Fmt.fmt_tokens(root.entry.context_used) + " / " + Fmt.fmt_tokens(root.entry.context_window) + " tokens" : "No context reading"
                    color: root.st.text_dim
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-4)
                }
            }
        }
    }
}
