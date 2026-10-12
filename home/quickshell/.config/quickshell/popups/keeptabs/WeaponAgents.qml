// home/quickshell/.config/quickshell/popups/keeptabs/WeaponAgents.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "KeeptabsFormat.js" as Fmt

// The Agents tab as the HL1 weapon-selection menu: a numbered bucket per state with its sessions stacked as weapons.
// The bucket holding the cursor opens wide and shows the selected session as a weapon card with context as its ammo bar.
// Contract as in AgentsView.
Item {
    id: root

    property var sessions: []
    property int selected: 0
    property int pick_exit: 0
    property var st: Style
    property var on_select: function (i) {}
    property var on_activate: function (id) {}
    property bool draws_footer: false

    readonly property var bucket_states: ["waiting", "done", "running", "idle"]
    readonly property color hl: Style.text_primary
    readonly property color hl_t: Style.text_muted
    readonly property real gap: 4
    readonly property real bar_h: 18
    readonly property real closed_w: Math.floor((root.width - root.gap * 3) * 0.2)
    readonly property real open_w: root.width - root.gap * 3 - root.closed_w * 3

    // Sessions arrive waiting, done, running, idle, so a bucket's items are contiguous and j/k order follows the buckets.
    readonly property var buckets: {
        const out = root.bucket_states.map(name => ({ name: name, items: [] }));
        root.sessions.forEach((session, index) => {
            const known = root.bucket_states.indexOf(session.state);
            out[known < 0 ? 3 : known].items.push({ session: session, index: index });
        });
        return out;
    }
    readonly property int open_bucket: {
        const current = root.sessions[root.selected];
        const known = current ? root.bucket_states.indexOf(current.state) : 0;
        return known < 0 ? 3 : known;
    }

    function ensure_visible(i) {
        for (let b = 0; b < root.buckets.length; b++) {
            const pos = root.buckets[b].items.findIndex(item => item.index === i);
            if (pos >= 0) {
                columns.itemAt(b).list.positionViewAtIndex(pos, ListView.Contain);
                return;
            }
        }
    }

    function ammo_color(pct) {
        return pct >= 85 ? Style.pal.error : root.hl;
    }

    Text {
        anchors.centerIn: parent
        visible: root.sessions.length === 0
        text: root.pick_exit === 0 ? "No agent sessions" : root.pick_exit === 127 ? "keeptabs-pick not available" : "keeptabs-pick failed"
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    Row {
        anchors.fill: parent
        visible: root.sessions.length > 0
        spacing: root.gap

        Repeater {
            id: columns
            model: root.buckets

            Item {
                id: column
                required property var modelData
                required property int index
                readonly property bool open: column.index === root.open_bucket
                readonly property alias list: bucket_list

                width: column.open ? root.open_w : root.closed_w
                height: parent.height

                Rectangle {
                    id: header
                    width: parent.width
                    height: root.bar_h
                    color: column.open ? root.hl : "transparent"
                    border.width: column.open ? 0 : 1
                    border.color: Style.hairline_dim

                    Text {
                        id: header_number
                        width: 17
                        height: parent.height
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: String(column.index + 1)
                        color: column.open ? Theme.bg_crust : root.hl
                        font.family: Style.number_font
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Rectangle {
                        x: header_number.width
                        width: 1
                        height: parent.height
                        color: column.open ? Qt.alpha(Theme.bg_crust, 0.4) : Style.hairline_dim
                    }

                    // Closed buckets are narrow; the name shrinks to fit rather than eliding to nothing.
                    Text {
                        x: header_number.width + 4
                        width: parent.width - x - 3
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 6
                        text: column.modelData.name.toUpperCase() + (column.open ? "  " + column.modelData.items.length : "")
                        color: column.open ? Theme.bg_crust : root.hl_t
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-6)
                        font.bold: true
                        font.letterSpacing: column.open ? 1.3 : 0.5
                    }
                }

                ListView {
                    id: bucket_list
                    y: root.bar_h + 2
                    width: parent.width
                    height: parent.height - y
                    clip: true
                    spacing: 3
                    model: column.modelData.items
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: weapon
                        required property var modelData
                        readonly property var session: weapon.modelData.session
                        readonly property bool current: weapon.modelData.index === root.selected
                        readonly property bool has_context: weapon.session.context_pct !== null && weapon.session.context_pct !== undefined
                        readonly property real pct: weapon.has_context ? Math.max(0, Math.min(100, weapon.session.context_pct)) : 0

                        width: bucket_list.width
                        height: weapon.current ? card.implicitHeight + 12 : Style.px(28)
                        color: weapon.current ? Style.selection_bg : "transparent"
                        border.width: 1
                        border.color: weapon.current ? Style.hairline : Style.hairline_dim

                        // Closed weapon: the title and a sliver of ammo.
                        Text {
                            visible: !weapon.current
                            x: 4
                            y: 3
                            width: parent.width - 8
                            elide: Text.ElideRight
                            text: weapon.session.title || "Untitled"
                            color: root.hl
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-4)
                        }

                        Rectangle {
                            visible: !weapon.current && weapon.has_context
                            x: 4
                            y: parent.height - 6
                            width: parent.width - 8
                            height: 2
                            color: Style.meter_off

                            Rectangle {
                                width: parent.width * weapon.pct / 100
                                height: parent.height
                                color: root.ammo_color(weapon.pct)
                            }
                        }

                        ColumnLayout {
                            id: card
                            visible: weapon.current
                            x: 6
                            y: 6
                            width: parent.width - 12
                            spacing: 3

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                text: weapon.session.title || "Untitled"
                                color: root.st.text_fg
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-2)
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                text: (weapon.session.agent || "claude") + " · " + (weapon.session.project || "")
                                color: root.hl_t
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-4)
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                text: (weapon.session.where || "") + " · " + Fmt.age(weapon.session.since)
                                color: root.hl_t
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-4)
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 6
                                Layout.topMargin: 2
                                visible: weapon.has_context
                                color: Style.meter_off

                                Rectangle {
                                    width: parent.width * weapon.pct / 100
                                    height: parent.height
                                    color: root.ammo_color(weapon.pct)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    text: weapon.has_context ? Fmt.fmt_tokens(weapon.session.context_used) + "/" + Fmt.fmt_tokens(weapon.session.context_window) : "NO AMMO DATA"
                                    color: weapon.has_context ? root.ammo_color(weapon.pct) : root.st.text_dim
                                    font.family: Style.number_font
                                    font.pixelSize: root.st.fs(-2)
                                    font.bold: true
                                }

                                Text {
                                    visible: weapon.has_context
                                    text: weapon.has_context ? weapon.session.context_pct + "%" : ""
                                    color: root.hl_t
                                    font.family: Style.number_font
                                    font.pixelSize: root.st.fs(-4)
                                    font.bold: true
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.on_select(weapon.modelData.index);
                                root.on_activate(weapon.session.id);
                            }
                        }
                    }
                }
            }
        }
    }
}
