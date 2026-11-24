import QtQuick
import QtQuick.Layouts
import qs.core
import qs.theme
import qs.features.popups
import "KeeptabsFormat.js" as Fmt
import "Condition.js" as Condition

// The Agents tab as a Resident Evil status screen: the selected session's heart monitor and condition on top, and
// the whole party below, one row per session with its own small trace. Contract as in AgentsView.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    readonly property var current: root.sessions[root.selected] || null
    readonly property bool has_context: root.current !== null && root.current.context_pct !== null && root.current.context_pct !== undefined
    // The traces scroll only while the popup shows this tab and the machine is on mains power, as the bar's other
    // loops do; on battery they stand still.
    readonly property bool animating: Popups.open_name === "keeptabs" && root.visible && PowerSource.on_ac
    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_fg, text_dim: root.st.text_dim })

    function condition(state) {
        return Condition.look(state, { warning: Style.pal.warning, ok: Style.pal.ok, info: Style.pal.info, dim: root.st.text_dim });
    }

    function ensure_visible(i) {
        party_list.positionViewAtIndex(i, ListView.Contain);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        // --- Condition panel: the selected session ---
        Rectangle {
            id: panel
            readonly property var cond: root.condition(root.current ? root.current.state : "idle")

            Layout.fillWidth: true
            implicitHeight: panel_column.implicitHeight + 16
            radius: 6
            color: Qt.alpha(Theme.bg_shadow, 0.35)
            border.width: 2
            border.color: Style.frame_border_color

            ColumnLayout {
                id: panel_column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        id: monitor
                        Layout.fillWidth: true
                        Layout.preferredHeight: Style.px(64)
                        color: Qt.alpha(Theme.bg_shadow, 0.8)
                        border.width: 1
                        border.color: Qt.alpha(panel.cond.color, 0.25)

                        Repeater {
                            model: 14

                            Rectangle {
                                required property int index
                                x: (index + 1) * monitor.width / 15
                                width: 1
                                height: monitor.height
                                color: Qt.alpha(panel.cond.color, 0.12)
                            }
                        }

                        Rectangle {
                            y: monitor.height / 2
                            width: monitor.width
                            height: 1
                            color: Qt.alpha(panel.cond.color, 0.12)
                        }

                        EcgTrace {
                            anchors.fill: parent
                            anchors.margins: 6
                            beat: panel.cond.beat
                            line_color: panel.cond.color
                            line_width: Style.px(2.5)
                            beat_ms: panel.cond.ms
                            running: root.animating && root.current !== null
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: false
                        Layout.preferredWidth: Style.px(118)
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        Text {
                            text: "CONDITION"
                            color: Theme.theme_primary_light
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-5)
                            font.letterSpacing: 2
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.current ? panel.cond.word : "NO SIGNAL"
                            color: panel.cond.color
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(3)
                            font.bold: true
                            font.letterSpacing: 1
                            style: Text.Raised
                            styleColor: Style.text_shadow
                        }

                        Text {
                            visible: root.current !== null
                            text: root.current ? "for " + Fmt.age(root.current.since) : ""
                            color: root.st.text_muted
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: root.current ? (root.current.title || "Untitled") : root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
                        color: root.current ? Style.text_strong : root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    Text {
                        visible: root.current !== null
                        text: root.has_context ? root.current.context_pct + "%" : "--"
                        color: root.has_context ? Fmt.context_bar_color(root.current.context_pct, root.colors) : root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.current !== null
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: root.current ? [root.current.agent || "claude", root.current.project || "", root.current.where || ""].filter(x => x).join(" · ") : ""
                        color: root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }

                    Text {
                        visible: root.has_context
                        text: root.has_context ? Fmt.fmt_tokens(root.current.context_used) + " / " + Fmt.fmt_tokens(root.current.context_window) : ""
                        color: root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }
                }
            }
        }

        // --- Party: every session ---
        Text {
            Layout.topMargin: 2
            visible: root.sessions.length > 0
            text: "PARTY"
            color: Theme.theme_primary_light
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-5)
            font.letterSpacing: 3
        }

        ListView {
            id: party_list
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.sessions.length > 0
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: root.sessions
            currentIndex: root.selected

            delegate: Rectangle {
                id: member
                required property var modelData
                required property int index
                readonly property bool is_selected: member.index === root.selected
                readonly property var cond: root.condition(member.modelData.state)

                width: party_list.width
                height: Style.px(40)
                radius: 4
                color: member.is_selected ? Qt.alpha(member.cond.color, 0.12) : Qt.alpha(Theme.bg_shadow, 0.35)
                border.width: member.is_selected ? 2 : 1
                border.color: member.is_selected ? member.cond.color : Qt.alpha(Style.frame_border_color, 0.6)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: member.modelData.title || "Untitled"
                            color: member.is_selected ? Style.text_strong : root.st.text_fg
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: (member.modelData.project || "") + " · " + Fmt.age(member.modelData.since)
                            color: root.st.text_muted
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-5)
                        }
                    }

                    // Context fill, so every row shows it without selecting the session; blank without context data.
                    Text {
                        readonly property var pct: member.modelData.context_pct
                        readonly property bool known: pct !== null && pct !== undefined
                        Layout.preferredWidth: Style.px(40)
                        horizontalAlignment: Text.AlignRight
                        text: known ? pct + "%" : ""
                        color: known ? Fmt.context_bar_color(pct, root.colors) : root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                        font.bold: true
                    }

                    Rectangle {
                        Layout.preferredWidth: Style.px(84)
                        Layout.preferredHeight: Style.px(24)
                        color: Qt.alpha(Theme.bg_shadow, 0.8)

                        EcgTrace {
                            anchors.fill: parent
                            anchors.margins: 3
                            beat: member.cond.beat
                            line_color: member.cond.color
                            line_width: Style.px(1.5)
                            beat_ms: member.cond.ms
                            running: root.animating
                        }
                    }

                    Text {
                        Layout.preferredWidth: Style.px(58)
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: member.cond.word
                        color: member.cond.color
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.on_select(member.index);
                        root.on_activate(member.modelData.id);
                    }
                }
            }
        }

        // Keeps the panel at the top when the party list is hidden.
        Item {
            Layout.fillHeight: true
            visible: root.sessions.length === 0
        }
    }
}
