import QtQuick
import QtQuick.Layouts
import qs.ui.effects
import qs.components.nes
import qs.theme
import qs.services
import qs.popups.weather as Weather
import "../../components/nes/Slimes.js" as Slimes
import "KeeptabsFormat.js" as Fmt

// The Agents tab as a Dragon Quest party: a strip of four member windows paging around the selection, a message
// window spelling out the selected session, and a COMMAND window with a blinking cursor while it waits.
// Contract as AgentsView.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    readonly property bool moves_across: true
    readonly property int page_size: 4
    readonly property int page: Math.floor(root.selected / root.page_size)
    readonly property int page_count: Math.max(1, Math.ceil(root.sessions.length / root.page_size))
    readonly property var current: root.sessions.length > 0 ? root.sessions[Math.max(0, Math.min(root.selected, root.sessions.length - 1))] : null
    readonly property string current_state: root.current ? (root.current.state || "idle") : "idle"
    readonly property bool has_context: root.current !== null && root.current.context_pct !== null && root.current.context_pct !== undefined
    readonly property bool low: root.has_context && root.current.context_pct >= 85
    readonly property color low_color: Style.pal.warning
    readonly property bool animating: Popups.open_name === "keeptabs" && root.visible
    property bool beat: false

    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })

    readonly property var verbs: ({
        waiting: "awaits orders.",
        done: "defeated the task! Gained EXP.",
        running: "is fighting.",
        idle: "is asleep. ZZZ"
    })

    // One session as a Dragon Quest party member: a slime for its agent in a window named by the title, with H (context
    // left), M (context used) and L (time in this state) beneath. The border turns warning-coloured as context runs out.
    component PartyMemberWindow: Weather.DqWindow {
        id: member

        required property var session
        property bool is_selected: false
        // Flips on the popup's blink timer; waiting members hop with it.
        property bool beat: false
        property var st: Style

        readonly property bool has_context: member.session.context_pct !== null && member.session.context_pct !== undefined
        readonly property bool low: member.has_context && member.session.context_pct >= 85
        readonly property string state_name: member.session.state || "idle"
        readonly property bool codex: member.session.agent === "codex"
        readonly property color low_color: Style.pal.warning
        readonly property int pixel: 3

        title: member.session.title || "Untitled"
        color: member.state_name === "running" ? Style.pal.bg_surface : Theme.bg_crust
        border.color: member.low ? member.low_color : Theme.fg_strong

        function slime_colors(): var {
            const body = member.state_name === "idle" ? Style.pal.fg_muted : member.codex ? Style.pal.red : Style.pal.blue;
            const shine = member.state_name === "idle" ? Style.pal.fg_dim : member.codex ? Style.pal.bright_red : Style.pal.bright_blue;
            return [Style.pal.bg_crust, Style.pal.fg_strong, Style.pal.yellow, Style.pal.bright_yellow, body, shine, Style.pal.fg_dim, Style.pal.red];
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            anchors.topMargin: 10
            spacing: 2

            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Slimes.SIZE * member.pixel
                Layout.preferredHeight: Slimes.SIZE * member.pixel + member.pixel

                PixelSprite {
                    y: member.state_name === "waiting" && member.beat ? 0 : member.pixel
                    pixel: member.pixel
                    colors: member.slime_colors()
                    rows: member.state_name === "done" ? Slimes.KING_SLIME : Slimes.SLIME
                }

                Text {
                    visible: member.state_name === "idle"
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: "z"
                    color: Theme.fg_strong
                    font.family: member.st.font_family
                    font.pixelSize: member.st.fs(-5)
                    font.bold: true
                }
            }

            Repeater {
                model: [
                    { key: "H", value: member.has_context ? Fmt.fmt_tokens(Math.max(0, member.session.context_window - member.session.context_used)) : "--", hot: false },
                    { key: "M", value: member.has_context ? member.session.context_pct + "%" : "--", hot: member.low },
                    { key: "L", value: Fmt.age(member.session.since), hot: false }
                ]

                delegate: RowLayout {
                    id: stat
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: stat.modelData.key
                        color: member.is_selected ? Theme.fg_strong : member.st.text_dim
                        font.family: member.st.font_family
                        font.pixelSize: member.st.fs(-5)
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: stat.modelData.value
                        color: stat.modelData.hot ? member.low_color : member.is_selected ? Theme.fg_strong : member.st.text_muted
                        font.family: member.st.font_family
                        font.pixelSize: member.st.fs(-5)
                    }
                }
            }
        }

        Text {
            visible: member.is_selected
            x: 7
            y: 6
            text: "▶"
            color: Theme.fg_strong
            font.family: member.st.font_family
            font.pixelSize: member.st.fs(-5)
        }
    }

    // h/l and j/k both step one member through the whole list, so the strip pages when the step crosses its edge.
    function nav_target(i, dx, dy) {
        const n = root.sessions.length;
        return n === 0 ? 0 : ((i + dx + dy) % n + n) % n;
    }

    // The strip is derived from `selected`, so there is nothing to scroll.
    function ensure_visible(i) {}

    Timer {
        running: root.animating
        interval: 500
        repeat: true
        onTriggered: root.beat = !root.beat
        onRunningChanged: if (!running) root.beat = false
    }

    Text {
        anchors.centerIn: parent
        visible: root.sessions.length === 0
        text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.sessions.length > 0
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 6

            Repeater {
                model: root.sessions.slice(root.page * root.page_size, (root.page + 1) * root.page_size)

                delegate: Item {
                    id: slot
                    required property var modelData
                    required property int index
                    readonly property int session_index: root.page * root.page_size + slot.index

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: Style.px(100)

                    PartyMemberWindow {
                        anchors.fill: parent
                        session: slot.modelData
                        is_selected: slot.session_index === root.selected
                        beat: root.beat
                        st: root.st
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.on_select(slot.session_index);
                            root.on_activate(slot.modelData.id);
                        }
                    }
                }
            }

            // Pads a short last page so its windows keep the width of a full strip.
            Repeater {
                model: Math.max(0, root.page_size - root.sessions.slice(root.page * root.page_size, (root.page + 1) * root.page_size).length)

                delegate: Item {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignRight
            visible: root.page_count > 1
            text: (root.page > 0 ? "▲ " : "") + (root.page < root.page_count - 1 ? "▼ " : "") + (root.selected + 1) + "/" + root.sessions.length
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-4)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            Weather.DqWindow {
                Layout.fillWidth: true
                Layout.fillHeight: true
                border.color: root.low ? root.low_color : Theme.fg_strong

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: root.current ? (root.current.title || "Untitled") : ""
                        color: root.st.text_fg
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: root.current ? (root.current.project || "") + " · " + (root.current.where || "") + " · " + (root.current.agent || "claude") : ""
                        color: root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: root.current_state.toUpperCase() + " " + (root.verbs[root.current_state] || root.verbs.idle) + " (" + Fmt.age(root.current ? root.current.since : 0) + ")"
                        color: Fmt.state_color(root.current_state, root.colors)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        visible: root.has_context
                        text: root.has_context ? "Context " + root.current.context_pct + "% · " + Fmt.fmt_tokens(root.current.context_used) + "/" + Fmt.fmt_tokens(root.current.context_window) : ""
                        color: root.low ? root.low_color : root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }

                    Weather.BattleGauge {
                        Layout.fillWidth: true
                        visible: root.has_context
                        value: root.has_context ? root.current.context_pct / 100 : 0
                        fill_color: root.low ? root.low_color : Theme.fg_strong
                    }
                }
            }

            Weather.DqWindow {
                visible: root.current_state === "waiting"
                title: "COMMAND"
                Layout.preferredWidth: Style.px(96)
                Layout.fillHeight: true

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "▶"
                        opacity: root.beat || !root.animating ? 1 : 0
                        color: Theme.fg_strong
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-2)
                    }

                    Text {
                        text: "Focus"
                        color: Theme.fg_strong
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-2)
                    }
                }
            }
        }
    }
}
