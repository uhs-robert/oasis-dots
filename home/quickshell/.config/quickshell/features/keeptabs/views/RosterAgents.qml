import QtQuick
import QtQuick.Layouts
import qs.ui.gauges
import qs.ui.menu
import qs.theme
import qs.styles.reticle.widgets
import "KeeptabsFormat.js" as Fmt

// The Reticle Agents tab: a drone roster. Each session is a numbered unit with a ring gauge lit to its context,
// its state in tracked caps beside the title, and its details on a hairline with a tick scale.
// Inputs and callbacks are the contract in AgentsView.qml.
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
    // Other styles leave the hairline tokens transparent, so a borrowed roster falls back to the palette.
    readonly property color hairline: root.st.hairline.a > 0 ? root.st.hairline : Qt.alpha(Style.pal.fg_strong, 0.55)
    readonly property color hairline_dim: root.st.hairline_dim.a > 0 ? root.st.hairline_dim : Qt.alpha(Style.pal.fg_strong, 0.24)
    readonly property color selection_rule: root.st.selection_rule.a > 0 ? root.st.selection_rule : Qt.alpha(Style.pal.primary, 0.6)

    readonly property var state_words: ({ waiting: "AWAITING", done: "COMPLETE", running: "ACTIVE" })

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
        font.letterSpacing: 2
        font.capitalization: Font.AllUppercase
    }

    ListView {
        id: session_list
        anchors.fill: parent
        visible: root.sessions.length > 0
        clip: true
        spacing: 2
        model: root.sessions
        currentIndex: root.selected

        delegate: MenuRow {
            id: unit
            required property var modelData
            required property int index
            readonly property bool has_context: unit.modelData.context_pct !== null && unit.modelData.context_pct !== undefined
            readonly property bool waiting: unit.modelData.state === "waiting"
            readonly property color ring_color: unit.waiting ? root.st.meter_hot : unit.has_context ? Fmt.context_bar_color(unit.modelData.context_pct, root.colors) : root.st.text_dim

            width: session_list.width
            height: Style.px(46)
            selected: unit.index === root.selected

            Item {
                id: gauge_slot
                anchors.left: parent.left
                anchors.leftMargin: 4 + unit.inset
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 44

                RingGauge {
                    anchors.centerIn: parent
                    width: 36
                    color: unit.ring_color
                    value: unit.has_context ? unit.modelData.context_pct / 100 : 0
                    label: (unit.index + 1 < 10 ? "0" : "") + (unit.index + 1)
                    label_size: 11
                }

                Reticle {
                    anchors.centerIn: parent
                    width: 44
                    height: 44
                    visible: unit.selected
                    color: root.st.text_strong
                }
            }

            ColumnLayout {
                anchors.left: gauge_slot.right
                anchors.leftMargin: 4
                anchors.right: parent.right
                anchors.rightMargin: 8 + unit.key_space
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: root.state_words[unit.modelData.state] || "STANDBY"
                        color: unit.fg(unit.waiting ? root.st.meter_hot : Fmt.state_color(unit.modelData.state, root.colors))
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                        font.bold: true
                        font.letterSpacing: 2.5
                    }

                    RowLabel {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        label: unit.modelData.title || "Untitled"
                        color: unit.fg(root.st.text_fg)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                    }

                    Text {
                        text: unit.has_context ? unit.modelData.context_pct + "% " + Fmt.fmt_tokens(unit.modelData.context_used) + "/" + Fmt.fmt_tokens(unit.modelData.context_window) : "--"
                        color: unit.fg(root.st.text_dim)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }
                }

                RowLabel {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    label: (unit.modelData.agent || "claude") + " · " + (unit.modelData.project || "") + " · " + (unit.modelData.where || "") + " · " + Fmt.age(unit.modelData.since)
                    color: unit.fg(root.st.text_muted)
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.hairline_dim
                    }

                    TickScale {
                        width: parent.width
                        height: parent.height
                        step: 8
                        major_every: 5
                        major_length: 4
                        minor_length: 2
                        major_color: root.hairline
                        minor_color: root.hairline_dim
                    }
                }
            }

            // MenuRow draws the style's own rule; a borrowed roster draws the palette one.
            Rectangle {
                visible: unit.selected && root.st.selection_rule.a === 0
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: root.selection_rule
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.on_select(unit.index);
                    root.on_activate(unit.modelData.id);
                }
            }
        }
    }
}
