pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../components/gameboy" as Gameboy
import "../../theme"
import "../../services"
import "KeeptabsFormat.js" as Fmt
import "PkmnSprites.js" as Sprites

// The Agents tab as a Pokemon party screen: a row per session (sprite, name, :L age, HP = context left, status)
// over a text box that spells out the selected one. Contract as in AgentsView.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    readonly property bool is_open: Popups.open_name === "keeptabs"
    readonly property bool mono: Style.device_model === "dmg"
    readonly property var shades: Style.pixel_shades
    readonly property var current: root.sessions[root.selected]
    readonly property int row_height: Style.px(34)
    readonly property int cursor_gap: 12
    readonly property var status_tags: ({ waiting: "!", done: "FIN", running: "RUN", idle: "SLP" })

    function ensure_visible(i) {
        party_list.positionViewAtIndex(i, ListView.Contain);
    }

    function short(text, max) {
        return text.length > max ? text.slice(0, max - 1) + "…" : text;
    }

    function title_of(session) {
        return session.title || "Untitled";
    }

    // Shades alone on the Original (darker as it drains, never the track's shade 1); green, yellow, red on the Color like the games' HP bar.
    function hp_color(left_pct) {
        if (root.mono) return left_pct > 50 ? root.shades[2] : root.shades[3];
        return left_pct > 50 ? Style.pal.ok : left_pct > 20 ? Style.pal.warning : Style.pal.error;
    }

    function has_context(session) {
        return session.context_pct !== null && session.context_pct !== undefined;
    }

    // Pokemon levels run 1-100, so the context percentage is the level.
    function level_of(session) {
        return Math.max(1, Math.min(100, Math.round(session.context_pct)));
    }

    function message(session) {
        const name = root.short(root.title_of(session), 16);
        if (session.state === "waiting") return name + " wants to make a decision!";
        if (session.state === "done") return root.has_context(session) ? name + " grew to level " + root.level_of(session) + "!" : name + " is done!";
        if (session.state === "idle") return name + " is fast asleep.";
        return root.title_of(session);
    }

    function stats_line(session) {
        const base = (session.state || "idle").toUpperCase() + " " + Fmt.age(session.since);
        if (!root.has_context(session)) return base;
        return base + "  CTX " + session.context_pct + "% " + Fmt.fmt_tokens(session.context_used) + "/" + Fmt.fmt_tokens(session.context_window);
    }

    Text {
        anchors.centerIn: parent
        visible: root.sessions.length === 0
        text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
        color: root.shades[2]
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.sessions.length > 0
        spacing: 4

        ListView {
            id: party_list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.sessions
            currentIndex: root.selected

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool picked: row.index === root.selected
                readonly property bool known: root.has_context(row.modelData)
                readonly property real left_pct: row.known ? Math.max(0, Math.min(100, 100 - row.modelData.context_pct)) : 0
                readonly property bool alive: root.is_open && root.visible && row.modelData.state === "running"

                width: party_list.width
                height: root.row_height

                Gameboy.PartyBox {
                    x: root.cursor_gap
                    width: parent.width - root.cursor_gap
                    height: parent.height
                    selected: row.picked
                }

                Gameboy.PartyCursor {
                    visible: row.picked
                    pixel: 2
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    id: sprite_slot
                    x: root.cursor_gap + 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    property real hop: 0

                    SequentialAnimation on hop {
                        running: row.alive
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: -2; duration: 220 }
                        NumberAnimation { to: 0; duration: 220 }
                    }

                    PixelSprite {
                        x: Math.round((parent.width - width) / 2)
                        y: Math.round((parent.height - height) / 2 + sprite_slot.hop)
                        pixel: 2
                        rows: Sprites.sprite(row.modelData.agent)
                    }
                }

                ColumnLayout {
                    anchors.left: sprite_slot.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: root.title_of(row.modelData)
                            color: row.modelData.state === "idle" ? root.shades[2] : root.shades[3]
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-4)
                        }

                        Text {
                            text: ":L" + Fmt.age(row.modelData.since)
                            color: root.shades[3]
                            font.family: root.st.title_font_family
                            font.pixelSize: 8
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        Text {
                            text: "HP"
                            color: root.shades[2]
                            font.family: root.st.title_font_family
                            font.pixelSize: 8
                        }

                        SegBar {
                            Layout.preferredWidth: Style.px(84)
                            Layout.preferredHeight: 6
                            count: 14
                            gap: 1
                            last_lit: row.known ? Math.round(row.left_pct / 100 * 14) - 1 : -1
                            on_color: root.hp_color(row.left_pct)
                            off_color: root.shades[1]
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideLeft
                            horizontalAlignment: Text.AlignRight
                            text: row.known ? Fmt.fmt_tokens(row.modelData.context_window * row.left_pct / 100) + "/" + Fmt.fmt_tokens(row.modelData.context_window) : "--"
                            color: root.shades[2]
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-4)
                        }

                        Text {
                            Layout.preferredWidth: Style.px(30)
                            horizontalAlignment: Text.AlignRight
                            text: root.status_tags[row.modelData.state] || "SLP"
                            color: row.modelData.state === "waiting" && !root.mono ? Style.pal.warning : root.shades[3]
                            visible: row.modelData.state !== "waiting" || Style.caret_phase || !root.is_open
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-4)
                            font.bold: row.modelData.state === "waiting"
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.on_select(row.index);
                        root.on_activate(row.modelData.id);
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.px(82)

            PixelBox {
                id: text_box
                anchors.fill: parent
                fill: root.shades[0]
                rings: [root.shades[2], root.shades[0], root.shades[3]]
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: text_box.edge + 4
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.current ? root.message(root.current) : ""
                    color: root.shades[3]
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-4)
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.current ? (root.current.agent || "claude") + " · " + (root.current.project || "") + " · " + (root.current.where || "") : ""
                    color: root.shades[2]
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-4)
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.current ? root.stats_line(root.current) : ""
                    color: root.shades[2]
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-4)
                }
            }

            // Past six rows the party spills into the next box; the counter says where in it the cursor is.
            Text {
                visible: root.sessions.length > 6
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: text_box.edge + 4
                anchors.bottomMargin: text_box.edge + 2
                text: (root.selected + 1) + "/" + root.sessions.length
                color: root.shades[3]
                font.family: root.st.title_font_family
                font.pixelSize: 8
            }
        }
    }
}
