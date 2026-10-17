import QtQuick
import QtQuick.Layouts
import qs.ui.menu
import qs.components.snes as Snes
import qs.services
import qs.theme
import "KeeptabsFormat.js" as Fmt

// The Agents tab as the FF6 battle windows: the selected session's details on the left, the party on the right.
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

    readonly property var current: root.sessions.length > 0 ? root.sessions[Math.max(0, Math.min(root.selected, root.sessions.length - 1))] : null
    readonly property bool open: root.visible && Popups.open_name === "keeptabs"
    readonly property real row_height: Style.px(40)
    readonly property bool has_context: !!root.current && root.current.context_pct !== null && root.current.context_pct !== undefined

    function ensure_visible(i) {
        party_list.positionViewAtIndex(i, ListView.Contain);
    }

    function state_label(state) {
        return state === "waiting" ? "Waiting" : state === "running" ? "Running" : state === "done" ? "Done" : "Idle";
    }

    // Looping 0..1 clock for the ATB fills and the waiting flash; stopped while the popup is closed.
    property real phase: 0
    NumberAnimation on phase {
        running: root.open && root.sessions.length > 0
        from: 0
        to: 1
        duration: 2400
        loops: Animation.Infinite
    }

    Snes.SnesWindow {
        anchors.fill: parent
        visible: root.sessions.length === 0

        Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -parent.drop / 2
            width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
            color: Theme.fg_strong
            style: Text.Raised
            styleColor: Style.text_shadow
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
        }
    }

    RowLayout {
        anchors.fill: parent
        visible: root.sessions.length > 0
        spacing: 2

        Snes.SnesWindow {
            id: detail_window
            Layout.preferredWidth: Style.px(118)
            Layout.fillHeight: true

            ColumnLayout {
                x: 10
                y: 9
                width: detail_window.width - 20 - detail_window.drop
                height: detail_window.height - 18 - detail_window.drop
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: root.current ? (root.current.title || "Untitled") : ""
                    color: Theme.fg_strong
                    style: Text.Raised
                    styleColor: Style.text_shadow
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }

                Repeater {
                    model: root.current ? [
                        ["PROJECT", root.current.project || "-"],
                        ["WHERE", root.current.where || "-"],
                        ["AGENT", root.current.agent || "claude"],
                        [root.state_label(root.current.state || "idle").toUpperCase(), Fmt.age(root.current.since)],
                        ["CONTEXT", root.has_context ? root.current.context_pct + "%" : "-"],
                        ["TOKENS", root.has_context ? Fmt.fmt_tokens(root.current.context_used) + "/" + Fmt.fmt_tokens(root.current.context_window) : "-"]
                    ] : []

                    ColumnLayout {
                        id: detail_row
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: detail_row.modelData[0]
                            color: Theme.theme_primary_light
                            style: Text.Raised
                            styleColor: Style.text_shadow
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-5)
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: detail_row.modelData[1]
                            color: Theme.fg_strong
                            style: Text.Raised
                            styleColor: Style.text_shadow
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        Snes.SnesWindow {
            id: party_window
            Layout.fillWidth: true
            Layout.fillHeight: true
            lit: true

            ListView {
                id: party_list
                x: 8
                y: 8
                width: party_window.width - 16 - party_window.drop
                height: party_window.height - 16 - party_window.drop
                clip: true
                spacing: 0
                model: root.sessions
                currentIndex: root.selected
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: party_item
                    required property var modelData
                    required property int index

                    width: party_list.width
                    height: root.row_height

                    // Derived here rather than in a row component: a URL-loaded view cannot instantiate its siblings (#531).
                    readonly property string agent_state: party_item.modelData.state || "idle"
                    readonly property bool selected: party_item.index === root.selected
                    readonly property bool has_context: party_item.modelData.context_pct !== null && party_item.modelData.context_pct !== undefined
                    readonly property bool critical: party_item.has_context && party_item.modelData.context_pct >= 85
                    readonly property bool flash_on: Math.floor(root.phase * 4) % 2 === 0
                    readonly property string hp_text: party_item.has_context ? Fmt.fmt_tokens(Math.max(0, party_item.modelData.context_window - party_item.modelData.context_used)) + "/" + Fmt.fmt_tokens(party_item.modelData.context_window) : "--"
                    readonly property string tag: party_item.agent_state === "done" ? "Victory" : party_item.agent_state === "waiting" ? "Ready" : ""

                    HandCursor {
                        visible: party_item.selected
                        x: 2 + (party_item.agent_state === "waiting" && party_item.flash_on ? 2 : 0)
                        y: 3
                        width: 17
                        height: 11
                    }

                    ColumnLayout {
                        x: 22
                        width: party_item.width - x
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            RowLabel {
                                id: name_text
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                label: party_item.modelData ? (party_item.modelData.title || "Untitled") : ""
                                color: party_item.agent_state === "idle" ? Theme.fg_muted : party_item.agent_state === "done" ? Theme.fg_strong : Theme.theme_secondary
                                style: Text.Raised
                                styleColor: Style.text_shadow
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-2)
                            }

                            Text {
                                text: party_item.hp_text
                                color: party_item.critical ? Style.pal.warning : Theme.fg_strong
                                style: Text.Raised
                                styleColor: Style.text_shadow
                                font.family: Style.number_font
                                font.pixelSize: root.st.fs(-3)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Snes.SnesGauge {
                                Layout.fillWidth: true
                                implicitHeight: 6
                                dim: party_item.agent_state === "idle"
                                value: party_item.agent_state === "waiting" ? 1 : party_item.agent_state === "running" ? (root.phase + party_item.index * 0.17) % 1 : party_item.agent_state === "done" ? 1 : 0.5
                                opacity: party_item.agent_state === "waiting" && !party_item.flash_on ? 0.45 : 1
                            }

                            Text {
                                Layout.preferredWidth: party_item.tag === "" ? 0 : implicitWidth
                                visible: party_item.tag !== ""
                                text: party_item.tag
                                color: party_item.agent_state === "done" ? Theme.fg_strong : Theme.theme_label
                                style: Text.Raised
                                styleColor: Style.text_shadow
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-5)
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.on_select(party_item.index);
                            root.on_activate(party_item.modelData.id);
                        }
                    }
                }
            }

            Text {
                visible: !party_list.atYBeginning
                anchors.top: parent.top
                anchors.topMargin: -2
                x: party_window.width - party_window.drop - width - 10
                text: "▲"
                color: Theme.fg_strong
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-5)
            }

            Text {
                visible: !party_list.atYEnd
                anchors.bottom: parent.bottom
                anchors.bottomMargin: party_window.drop - 2
                x: party_window.width - party_window.drop - width - 10
                text: "▼"
                color: Theme.fg_strong
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-5)
            }
        }
    }
}
