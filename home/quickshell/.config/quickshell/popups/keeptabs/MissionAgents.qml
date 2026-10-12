// home/quickshell/.config/quickshell/popups/keeptabs/MissionAgents.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../components/goldeneye" as Goldeneye
import "../../lock/skins/goldeneye" as Watch
import "../../theme"
import "../../theme/Watch.js" as W
import "KeeptabsFormat.js" as Fmt

// GoldenEye's Mission Status: each session is an objective, with the selected one's context on the watch dial above.
// Inputs and callbacks are the AgentsView contract.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    readonly property var current: root.sessions[Math.max(0, Math.min(root.sessions.length - 1, root.selected))]
    readonly property bool has_context: !!root.current && root.current.context_pct !== null && root.current.context_pct !== undefined
    readonly property var used_parts: root.has_context ? root.token_parts(root.current.context_used) : { digits: "--", suffix: "" }

    // The seven-segment font has no k or M, so the magnitude letter travels as the unit.
    function token_parts(n) {
        const text = Fmt.fmt_tokens(n);
        const suffix = text.replace(/[0-9.]/g, "");
        return { digits: text.slice(0, text.length - suffix.length), suffix: suffix };
    }

    function status_text(state) {
        if (state === "running") return "IN PROGRESS";
        if (state === "waiting") return "AWAITING ORDERS";
        if (state === "done") return "COMPLETED";
        return "STANDBY";
    }

    function status_color(state) {
        if (state === "running") return Style.pal.info;
        if (state === "waiting") return Style.pal.error;
        if (state === "done") return Style.pal.ok;
        return Style.wk.dim;
    }

    function ensure_visible(i) {
        objective_list.positionViewAtIndex(i, ListView.Contain);
    }

    // Goldeneye's own popup frame already draws the green panel; a borrowed layout draws it here.
    Watch.PanelShape {
        anchors.fill: parent
        visible: !root.st.frame_watch
        cut: 12
        notches: false
        top_color: Style.wk.panel_top
        bottom_color: Style.wk.panel_bottom
        edge: Style.wk.edge
    }

    Text {
        anchors.centerIn: parent
        visible: root.sessions.length === 0
        text: (root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed").toUpperCase()
        color: root.pick_exit === 0 ? Style.wk.dim : Style.pal.error
        font.family: W.mono_font
        font.pixelSize: root.st.fs(-2)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6
        visible: root.sessions.length > 0

        Goldeneye.GaugeHeader {
            Layout.fillWidth: true
            size: Style.px(84)
            value: root.has_context ? root.current.context_pct / 100 : 0
            label: "CONTEXT"
            readout: root.has_context ? "" : "--"

            Goldeneye.ReadoutLine {
                Layout.fillWidth: true
                label: "MISSION"
                text: root.current ? (root.current.title || "Untitled").toUpperCase() : ""
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Goldeneye.ReadoutLine {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    label: "AGENT"
                    text: root.current ? (root.current.agent || "claude").toUpperCase() : ""
                }

                Goldeneye.ReadoutLine {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    label: root.has_context ? "USED / " + Fmt.fmt_tokens(root.current.context_window).toUpperCase() : "USED"
                    digits: root.used_parts.digits
                    unit: root.has_context ? root.used_parts.suffix : ""
                }
            }
        }

        ListView {
            id: objective_list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.sessions
            currentIndex: root.selected

            delegate: MenuRow {
                id: objective
                required property var modelData
                required property int index
                readonly property bool has_context: objective.modelData.context_pct !== null && objective.modelData.context_pct !== undefined

                width: objective_list.width
                height: Style.px(38)
                selected: objective.index === root.selected

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6 + objective.inset
                    anchors.rightMargin: 6 + objective.key_space
                    anchors.topMargin: 2
                    anchors.bottomMargin: 2
                    spacing: 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: (objective.modelData.title || "Untitled").toUpperCase()
                            color: objective.fg(Style.wk.lit)
                            font.family: W.mono_font
                            font.pixelSize: root.st.fs(-2)
                        }

                        Text {
                            text: root.status_text(objective.modelData.state)
                            color: objective.fg(root.status_color(objective.modelData.state))
                            font.family: W.mono_font
                            font.pixelSize: root.st.fs(-4)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: ((objective.modelData.project || "") + " · " + (objective.modelData.where || "") + " · " + Fmt.age(objective.modelData.since)).toUpperCase()
                            color: objective.fg(Style.wk.soft)
                            font.family: W.mono_font
                            font.pixelSize: root.st.fs(-4)
                        }

                        Goldeneye.SegmentStrip {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.rightMargin: 4
                            count: 8
                            seg_width: 4
                            seg_height: 8
                            value: objective.has_context ? objective.modelData.context_pct / 100 : 0
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.on_select(objective.index);
                        root.on_activate(objective.modelData.id);
                    }
                }
            }
        }
    }
}
