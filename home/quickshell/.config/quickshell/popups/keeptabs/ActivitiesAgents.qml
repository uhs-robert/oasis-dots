import QtQuick
import QtQuick.Layouts
import qs.components.modern as Modern
import qs.theme
import qs.services
import "KeeptabsFormat.js" as Fmt

// The Agents tab as a stack of Live Activity cards. Same contract as AgentsView.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    readonly property bool animate: root.visible && Popups.open_name === "keeptabs"
    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })

    function ensure_visible(i) {
        session_list.positionViewAtIndex(i, ListView.Contain);
    }

    function pill_color(state) {
        if (state === "waiting") return Style.pal.warning;
        if (state === "done") return Style.pal.ok;
        if (state === "running") return root.st.text_primary;
        return root.st.text_dim;
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
        spacing: 6
        model: root.sessions
        currentIndex: root.selected

        delegate: Modern.CardSurface {
            id: card
            required property var modelData
            required property int index
            readonly property string session_state: card.modelData.state || "idle"
            readonly property bool has_context: card.modelData.context_pct !== null && card.modelData.context_pct !== undefined
            readonly property color accent: root.pill_color(card.session_state)

            width: session_list.width
            height: Style.px(52)
            selected: card.index === root.selected

            Modern.AccentTile {
                id: tile
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                size: Style.px(34)
                glyph: (card.modelData.agent || "claude") === "claude" ? "\u{f06a9}" : "\u{f0169}"
                dimmed: card.session_state === "idle"
            }

            ColumnLayout {
                anchors.left: tile.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 6
                anchors.bottomMargin: 7
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: card.modelData.title || "Untitled"
                        color: card.selected ? root.st.tab_active_fg : root.st.text_fg
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                        font.bold: true
                    }

                    Rectangle {
                        Layout.preferredWidth: pill_text.implicitWidth + 12
                        Layout.preferredHeight: pill_text.implicitHeight + 2
                        radius: height / 2
                        color: card.session_state === "idle" ? "transparent" : Qt.alpha(card.accent, 0.2)

                        Row {
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                id: spinner
                                visible: card.session_state === "running"
                                text: "\u{f021}"
                                color: card.accent
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-3)
                                anchors.verticalCenter: parent.verticalCenter

                                RotationAnimator on rotation {
                                    running: spinner.visible && root.animate
                                    from: 0
                                    to: 360
                                    duration: 1200
                                    loops: Animation.Infinite
                                }
                            }

                            Text {
                                id: pill_text
                                text: card.session_state === "done" ? "\u{f00c} Done" : card.session_state === "waiting" ? "Waiting" : card.session_state === "running" ? "Running" : "Idle"
                                color: card.accent
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-3)
                                font.bold: card.session_state !== "idle"
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: (card.modelData.agent || "claude") + " · " + (card.modelData.project || "") + " · " + (card.modelData.where || "")
                        color: card.selected ? root.st.tab_active_fg : root.st.text_muted
                        opacity: card.selected ? 0.75 : 1
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }

                    // Its own slot, so the age is never the part that gets elided.
                    Text {
                        horizontalAlignment: Text.AlignRight
                        text: Fmt.age(card.modelData.since)
                        color: card.selected ? root.st.tab_active_fg : root.st.text_muted
                        opacity: card.selected ? 0.75 : 1
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }

                    Text {
                        visible: card.has_context
                        text: card.has_context ? card.modelData.context_pct + "% · " + Fmt.fmt_tokens(card.modelData.context_used) + "/" + Fmt.fmt_tokens(card.modelData.context_window) : ""
                        color: card.has_context ? Fmt.context_bar_color(card.modelData.context_pct, root.colors) : root.st.text_dim
                        font.family: root.st.mono_font
                        font.pixelSize: root.st.fs(-4)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 3
                    visible: card.has_context
                    radius: height / 2
                    color: Qt.alpha(root.st.text_fg, 0.15)

                    Rectangle {
                        width: card.has_context ? parent.width * Math.max(0, Math.min(100, card.modelData.context_pct)) / 100 : 0
                        height: parent.height
                        radius: height / 2
                        color: card.has_context ? Fmt.context_bar_color(card.modelData.context_pct, root.colors) : "transparent"
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.on_select(card.index);
                    root.on_activate(card.modelData.id);
                }
            }
        }
    }
}
