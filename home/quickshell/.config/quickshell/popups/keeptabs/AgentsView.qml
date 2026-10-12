// home/quickshell/.config/quickshell/popups/keeptabs/AgentsView.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "KeeptabsFormat.js" as Fmt

// The Agents tab: one row per session, waiting first. This is the contract every layout's Agents view
// (keeptabs/<prefix>Agents.qml) implements, set by the popup through Qt.binding:
//   sessions, selected, pick_exit, st  read-only inputs; st is the popup's Style (or Style.small)
//   on_select(i)                       the row at i was clicked; the popup owns `selected`
//   on_activate(id)                    focus that session and close the popup
//   ensure_visible(i)                  called by the popup after it moves `selected`, to scroll row i into view
//   draws_footer                       true when the view draws its own key help, which hides the shared footer
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

    function ensure_visible(i) {
        session_list.positionViewAtIndex(i, ListView.Contain);
    }

    Text {
        anchors.centerIn: parent
        visible: root.sessions.length === 0
        text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    ListView {
        id: session_list
        anchors.fill: parent
        visible: root.sessions.length > 0
        clip: true
        spacing: 4
        model: root.sessions
        currentIndex: root.selected

        delegate: MenuRow {
            id: session_row
            required property var modelData
            required property int index
            readonly property bool has_context: session_row.modelData.context_pct !== null && session_row.modelData.context_pct !== undefined

            width: session_list.width
            height: Style.px(46)
            selected: session_row.index === root.selected

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 6 + session_row.inset
                anchors.rightMargin: 6 + session_row.key_space
                anchors.topMargin: 3
                anchors.bottomMargin: 3
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: (session_row.modelData.state || "idle").toUpperCase()
                        color: session_row.fg(Fmt.state_color(session_row.modelData.state, root.colors))
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-2)
                        font.bold: true
                    }

                    RowLabel {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        label: session_row.modelData.title || "Untitled"
                        color: session_row.fg(root.st.text_fg)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLabel {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        label: (session_row.modelData.agent || "claude") + " · " + (session_row.modelData.project || "") + " · " + (session_row.modelData.where || "") + " · " + Fmt.age(session_row.modelData.since)
                        color: session_row.fg(root.st.text_muted)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }

                    Text {
                        visible: session_row.has_context
                        text: session_row.has_context ? session_row.modelData.context_pct + "% · " + Fmt.fmt_tokens(session_row.modelData.context_used) + "/" + Fmt.fmt_tokens(session_row.modelData.context_window) : ""
                        color: session_row.fg(root.st.text_dim)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }
                }

                Meter {
                    Layout.fillWidth: true
                    visible: session_row.has_context && root.st.segmented_levels
                    implicitHeight: 4
                    segment_count: 40
                    value: session_row.has_context ? session_row.modelData.context_pct / 100 : 0
                    on_color: session_row.has_context ? Fmt.context_bar_color(session_row.modelData.context_pct, root.colors) : root.st.meter_on
                    on_selection: session_row.selected
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: session_row.has_context ? 3 : 0
                    visible: session_row.has_context && !root.st.segmented_levels
                    radius: Style.radius(1.5)
                    color: Style.pal.bg_surface

                    Rectangle {
                        width: session_row.has_context ? parent.width * Math.max(0, Math.min(100, session_row.modelData.context_pct)) / 100 : 0
                        height: parent.height
                        radius: Style.radius(1.5)
                        color: session_row.has_context ? Fmt.context_bar_color(session_row.modelData.context_pct, root.colors) : "transparent"
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.on_select(session_row.index);
                    root.on_activate(session_row.modelData.id);
                }
            }
        }
    }
}
