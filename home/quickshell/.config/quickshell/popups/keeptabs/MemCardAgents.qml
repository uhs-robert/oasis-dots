import QtQuick
import QtQuick.Layouts
import "../../components/ps1" as Ps1
import "../../theme"
import "../../services"
import "KeeptabsFormat.js" as Fmt

// The Agents tab as the PS1 BIOS memory card manager: one save block per session on a 5x3 card, and the
// selected save's info panel under it. Contract as in AgentsView.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    readonly property int card_blocks: 15
    readonly property int columns: 5
    readonly property bool moves_across: true
    readonly property int page: Math.floor(Math.max(0, root.selected) / root.card_blocks)
    readonly property int page_count: Math.max(1, Math.ceil(root.sessions.length / root.card_blocks))
    readonly property var current: root.sessions[root.selected] || null
    readonly property bool has_context: root.current !== null && root.current.context_pct !== null && root.current.context_pct !== undefined
    readonly property bool animating: Popups.open_name === "keeptabs" && root.visible
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

    // The card shows the page holding `selected`, so there is nothing to scroll.
    function ensure_visible(i) {}

    function age_number(since) {
        return Fmt.age(since).slice(0, -1);
    }

    function age_unit(since) {
        return Fmt.age(since).slice(-1);
    }

    // Used blocks of a 15-block row for a percentage; any use at all shows at least one.
    function blocks_used(pct) {
        return pct > 0 ? Math.max(1, Math.min(root.card_blocks, Math.round(pct * root.card_blocks / 100))) : 0;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Grid {
                id: card
                columns: root.columns
                spacing: 6

                Repeater {
                    model: root.card_blocks

                    Item {
                        id: slot
                        required property int index
                        readonly property int session_index: root.page * root.card_blocks + slot.index
                        readonly property var session: root.sessions[slot.session_index] || null
                        readonly property bool used: slot.session !== null
                        readonly property bool is_selected: slot.used && slot.session_index === root.selected
                        readonly property string agent_state: slot.used ? (slot.session.state || "idle") : ""

                        width: Style.px(44)
                        height: Style.px(44)

                        Ps1.MemBlock {
                            id: block
                            anchors.fill: parent
                            size: parent.width
                            lit: slot.is_selected || slot.agent_state === "done"
                            opacity: !slot.used ? 0.4 : slot.agent_state === "idle" ? 0.55 : 1
                            border.color: slot.agent_state === "waiting" ? Style.pal.error : slot.agent_state === "done" ? Style.pal.ok : block.lit ? Theme.theme_primary_light : Style.frame_border_color

                            Ps1.PackageIcon {
                                visible: slot.used
                                anchors.centerIn: parent
                                size: parent.width - 12
                                name: slot.used ? (slot.session.project || "") : ""
                            }
                        }

                        // The animated save icon of a block that needs you: a red wash that pulses while the popup is open.
                        Rectangle {
                            anchors.fill: parent
                            radius: block.radius
                            visible: slot.agent_state === "waiting"
                            color: Qt.alpha(Style.pal.error, 0.35)
                            opacity: 0.6

                            SequentialAnimation on opacity {
                                running: slot.agent_state === "waiting" && root.animating
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.1; duration: 450 }
                                NumberAnimation { to: 0.9; duration: 450 }
                            }
                        }

                        Rectangle {
                            visible: slot.is_selected
                            anchors.fill: parent
                            anchors.margins: -3
                            radius: block.radius + 2
                            color: "transparent"
                            border.width: 2
                            border.color: Style.text_strong
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: slot.used
                            onClicked: {
                                root.on_select(slot.session_index);
                                root.on_activate(slot.session.id);
                            }
                        }
                    }
                }
            }
        }

        // One label line under the card, so PAGE n/m never competes with the card for width.
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: "MEMORY CARD"
                color: Theme.theme_primary_light
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-5)
            }

            Text {
                text: "PAGE " + (root.page + 1) + "/" + root.page_count
                color: root.st.text_muted
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-5)
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: "FREE " + Math.max(0, root.card_blocks - Math.max(0, root.sessions.length - root.page * root.card_blocks)) + " BLOCKS"
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-5)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 6
            color: Qt.alpha(Theme.bg_shadow, 0.35)
            border.width: 2
            border.color: Style.frame_border_color
            clip: true

            Text {
                anchors.fill: parent
                anchors.margins: 8
                visible: root.sessions.length === 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.Wrap
                text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            ColumnLayout {
                visible: root.current !== null
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Ps1.MemBlock {
                        Layout.alignment: Qt.AlignTop
                        size: Style.px(34)
                        lit: true

                        Ps1.PackageIcon {
                            anchors.centerIn: parent
                            size: parent.width - 10
                            name: root.current ? (root.current.project || "") : ""
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: root.current ? (root.current.title || "Untitled") : ""
                            color: Style.text_strong
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-2)
                            style: Text.Raised
                            styleColor: Style.text_shadow
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.current ? (root.current.agent || "claude") + " · " + (root.current.project || "") : ""
                            color: Theme.theme_primary_light
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-4)
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: root.current ? (root.current.where || "") : ""
                    color: root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-4)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: (root.current ? (root.current.state || "idle") : "").toUpperCase()
                        color: root.current ? Fmt.state_color(root.current.state, root.colors) : root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                        font.bold: true
                    }

                    Text {
                        text: "FOR"
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-5)
                    }

                    Ps1.Digits {
                        text: root.current ? root.age_number(root.current.since) : ""
                        size: Style.px(16)
                    }

                    Text {
                        text: root.current ? root.age_unit(root.current.since) : ""
                        color: root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        text: String(root.selected + 1).padStart(2, "0") + "/" + String(root.sessions.length).padStart(2, "0")
                        color: Theme.theme_primary_light
                        font.family: Style.mono_font
                        font.pixelSize: root.st.fs(-4)
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "BLOCKS"
                        color: Theme.theme_primary_light
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-5)
                    }

                    Item {
                        id: used_row
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: Style.px(10)
                        readonly property real block_w: Math.max(2, (used_row.width - 2 * (root.card_blocks - 1)) / root.card_blocks)

                        Repeater {
                            model: root.card_blocks

                            Rectangle {
                                required property int index
                                readonly property bool used: root.has_context && index < root.blocks_used(root.current.context_pct)

                                x: index * (used_row.block_w + 2)
                                width: used_row.block_w
                                height: used_row.height
                                radius: 1
                                color: used ? Fmt.context_bar_color(root.current.context_pct, root.colors) : Qt.alpha(Theme.bg_shadow, 0.6)
                                border.width: 1
                                border.color: used ? Qt.lighter(color, 1.3) : Qt.alpha(Style.frame_border_color, 0.6)
                            }
                        }
                    }

                    Text {
                        text: root.has_context ? root.current.context_pct + "% " + Fmt.fmt_tokens(root.current.context_used) + "/" + Fmt.fmt_tokens(root.current.context_window) : "--"
                        color: root.st.text_fg
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-5)
                    }
                }
            }
        }
    }
}
