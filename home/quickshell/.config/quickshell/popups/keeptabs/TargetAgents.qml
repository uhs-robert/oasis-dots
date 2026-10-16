pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme
import qs.services
import qs.popups.weather
import "KeeptabsFormat.js" as Fmt

// The Agents tab as a targeting computer: the selected session in a CMD target window, the others as IFF-coloured contacts below.
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
    readonly property color vec: root.st.text_primary
    readonly property color lock: root.st.selection_brackets.a > 0 ? root.st.selection_brackets : Theme.theme_label
    readonly property bool is_open: Popups.open_name === "keeptabs"
    readonly property var target: root.sessions[root.selected] || null
    readonly property bool has_context: !!root.target && root.target.context_pct !== null && root.target.context_pct !== undefined
    readonly property real remaining: root.has_context ? Math.max(0, Math.min(100, 100 - root.target.context_pct)) : 0

    // 0 while the brackets stand wide of the CMD window, 1 once they are locked on.
    property real lock_close: 1

    // TIE paints the primary text green, the same as done, so running contacts take the info blue to stay distinct.
    function iff_color(state) {
        return state === "running" ? Theme.info : Fmt.state_color(state, root.colors);
    }

    function ensure_visible(i) {
        contact_list.positionViewAtIndex(i, ListView.Contain);
    }

    onSelectedChanged: if (root.is_open) lock_anim.restart()
    onIs_openChanged: if (!root.is_open) lock_anim.stop()

    NumberAnimation {
        id: lock_anim
        target: root
        property: "lock_close"
        from: 0
        to: 1
        duration: 240
        easing.type: Easing.OutCubic
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
        spacing: 6

        Item {
            id: cmd
            Layout.fillWidth: true
            Layout.preferredHeight: cmd_column.implicitHeight + 16

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(root.vec, 0.05)
                border.width: 1
                border.color: Qt.alpha(root.vec, 0.35)
            }

            FontMetrics {
                id: title_metrics
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-1)
            }

            ColumnLayout {
                id: cmd_column
                anchors.fill: parent
                anchors.margins: 8
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: ((root.target ? root.target.agent : "") || "claude").toUpperCase()
                        color: root.vec
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                        font.bold: true
                        font.letterSpacing: 1.5
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: ((root.target ? root.target.state : "") || "idle").toUpperCase()
                        color: root.iff_color(root.target ? root.target.state : "")
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                        font.bold: true
                    }

                    Text {
                        text: "RNG " + (root.target ? Fmt.age(root.target.since) : "")
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.ceil(title_metrics.height) * 2
                    verticalAlignment: Text.AlignTop
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: (root.target ? root.target.title : "") || "Untitled"
                    color: root.st.text_strong
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-1)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: "CARGO " + ((root.target ? root.target.project : "") || "--")
                        color: root.st.text_fg
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: "GRP " + ((root.target ? root.target.where : "") || "--")
                        color: root.st.text_fg
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: root.remaining > 50 || !root.has_context ? "SHLD" : "HULL"
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }

                    TickGauge {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignVCenter
                        value: root.remaining / 100
                        color: root.has_context && root.target.context_pct >= 85 ? root.lock : root.vec
                    }

                    Text {
                        text: root.has_context ? Fmt.fmt_tokens(root.target.context_used) + "/" + Fmt.fmt_tokens(root.target.context_window) : "--"
                        color: root.st.text_fg
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }
                }
            }

            CornerBrackets {
                anchors.fill: parent
                // The CMD window sits at the top of the view, so only the other three sides open wide; the top would reach the tab row.
                anchors.topMargin: 0
                anchors.leftMargin: -Math.round(8 * (1 - root.lock_close))
                anchors.rightMargin: anchors.leftMargin
                anchors.bottomMargin: anchors.leftMargin
                color: root.lock
                inset: 0
                arm: 10
                thickness: 1.5
                all_corners: true
            }
        }

        Text {
            text: "CONTACTS"
            color: root.st.text_muted
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-4)
            font.letterSpacing: 2
        }

        ListView {
            id: contact_list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 0
            model: root.sessions
            currentIndex: root.selected

            delegate: Rectangle {
                id: contact
                required property var modelData
                required property int index
                readonly property bool is_selected: contact.index === root.selected
                readonly property color iff: root.iff_color(contact.modelData.state)
                readonly property bool has_pct: contact.modelData.context_pct !== null && contact.modelData.context_pct !== undefined

                width: contact_list.width
                height: Style.px(22)
                color: contact.is_selected ? Qt.alpha(root.lock, 0.08) : "transparent"

                Text {
                    id: cursor
                    visible: contact.is_selected
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▸"
                    color: root.lock
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }

                RowLabel {
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    anchors.right: pct_text.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    label: contact.modelData.title || "Untitled"
                    color: contact.iff
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }

                Text {
                    id: pct_text
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: contact.has_pct ? contact.modelData.context_pct + "%" : "--"
                    color: contact.has_pct && contact.modelData.context_pct >= 85 ? root.lock : root.st.text_dim
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.on_select(contact.index);
                        root.on_activate(contact.modelData.id);
                    }
                }
            }

            footer: Text {
                width: contact_list.width
                height: root.sessions.length === 1 ? Style.px(26) : 0
                visible: root.sessions.length === 1
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: "NO OTHER CONTACTS"
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-4)
                font.letterSpacing: 2
            }
        }
    }
}
