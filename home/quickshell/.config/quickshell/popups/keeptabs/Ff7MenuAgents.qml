import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../components/ff7" as Ff7
import "../../services"
import "../../theme"
import "KeeptabsFormat.js" as Fmt

// The Agents tab as the FF7 main menu: a party window of sessions (LV = time in state, HP = context left,
// Limit bar = context used) with the Location and Time windows of the selected one below it.
// The contract is in AgentsView.qml.
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
    readonly property int visible_rows: 3
    readonly property int window_gap: 6
    readonly property int pad: 8
    readonly property bool animating: root.visible && Popups.open_name === "keeptabs"
    readonly property var current: root.sessions[root.selected] || null

    // 0..1 pulse for the waiting Limit bar
    property real flash: 0

    function ensure_visible(i) {
        party_list.positionViewAtIndex(i, ListView.Contain);
    }

    function has_context(s) {
        return s.context_pct !== null && s.context_pct !== undefined;
    }

    // HP is the context left, in thousands like FF7's four-digit HP.
    function hp_text(s) {
        if (!root.has_context(s)) return "--/--";
        return Fmt.fmt_tokens(Math.max(0, s.context_window - s.context_used)) + "/" + Fmt.fmt_tokens(s.context_window);
    }

    function state_label(state) {
        if (state === "done") return "LEVEL UP";
        return (state || "idle").toUpperCase();
    }

    SequentialAnimation on flash {
        running: root.animating && root.sessions.some(s => s.state === "waiting")
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 450; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 450; easing.type: Easing.InOutSine }
    }

    Ff7.Ff7Window {
        id: party_window
        visible: root.sessions.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: bottom_row.top
        anchors.bottomMargin: root.window_gap

        ListView {
            id: party_list
            anchors.fill: parent
            anchors.margins: root.pad
            clip: true
            model: root.sessions
            currentIndex: root.selected
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: member
                required property var modelData
                required property int index
                readonly property bool is_selected: member.index === root.selected
                readonly property bool ctx: root.has_context(member.modelData)
                readonly property bool waiting: member.modelData.state === "waiting"
                readonly property bool idle: member.modelData.state !== "waiting" && member.modelData.state !== "running" && member.modelData.state !== "done"
                readonly property real pct: member.ctx ? Math.max(0, Math.min(100, member.modelData.context_pct)) : 0
                readonly property color text_color: member.idle ? root.st.text_dim : root.st.text_fg

                width: party_list.width
                height: party_list.height / root.visible_rows

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 1
                    anchors.bottomMargin: 1
                    radius: Style.radius(3)
                    color: Qt.alpha(Theme.fg_strong, 0.12)
                    visible: member.is_selected
                }

                HandCursor {
                    visible: member.is_selected
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 18
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 6
                    anchors.topMargin: 3
                    anchors.bottomMargin: 3
                    spacing: 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: member.modelData.title || "Untitled"
                            color: member.text_color
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-1)
                        }

                        Text {
                            text: root.state_label(member.modelData.state)
                            color: Fmt.state_color(member.modelData.state, root.colors)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                            font.bold: true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "LV " + Fmt.age(member.modelData.since)
                            color: member.text_color
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }

                        Text {
                            text: "HP"
                            color: root.st.text_dim
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-4)
                        }

                        Text {
                            text: root.hp_text(member.modelData)
                            color: member.pct >= 85 ? Style.pal.warning : member.text_color
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }

                        AtbBar {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            implicitHeight: 5
                            value: member.ctx ? 1 - member.pct / 100 : 0
                            opacity: member.idle ? 0.5 : 1
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "LIMIT"
                            color: root.st.text_dim
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-4)
                        }

                        AtbBar {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            implicitHeight: 5
                            ticks: true
                            value: member.waiting ? 1 : member.pct / 100
                            fill_color: member.waiting ? Qt.tint(Style.pal.warning, Qt.alpha(Theme.fg_strong, 0.6 * root.flash)) : Fmt.context_bar_color(member.pct, root.colors)
                            shade_color: member.waiting ? fill_color : Qt.lighter(fill_color, 1.4)
                            opacity: member.idle ? 0.5 : 1
                        }

                        Text {
                            Layout.preferredWidth: Style.px(30)
                            horizontalAlignment: Text.AlignRight
                            text: member.ctx ? member.modelData.context_pct + "%" : "--"
                            color: member.text_color
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }
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
    }

    RowLayout {
        id: bottom_row
        visible: root.sessions.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.px(56)
        spacing: root.window_gap

        Ff7.Ff7Window {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Column {
                anchors.fill: parent
                anchors.margins: root.pad
                spacing: 2

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.current ? (root.current.project || "") + " · " + (root.current.where || "") : ""
                    color: root.st.text_fg
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.current && root.has_context(root.current) ? "Context " + Fmt.fmt_tokens(root.current.context_used) + "/" + Fmt.fmt_tokens(root.current.context_window) + " (" + root.current.context_pct + "%)" : "Context unknown"
                    color: root.st.text_dim
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                }
            }
        }

        Ff7.Ff7Window {
            Layout.preferredWidth: Style.px(96)
            Layout.fillHeight: true

            Column {
                anchors.fill: parent
                anchors.margins: root.pad
                spacing: 2

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.current ? (root.current.agent || "claude") : ""
                    color: root.st.text_fg
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.current ? Fmt.age(root.current.since) : ""
                    color: root.st.text_dim
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                }
            }
        }
    }

    Ff7.Ff7Window {
        visible: root.sessions.length === 0
        anchors.fill: parent

        Text {
            anchors.centerIn: parent
            width: parent.width - 2 * root.pad
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
        }
    }
}
