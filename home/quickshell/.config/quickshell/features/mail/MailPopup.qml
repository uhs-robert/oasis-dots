import QtQuick
import QtQuick.Layouts
import qs.ui.menu
import qs.theme
import qs.features.popups
import qs.features.popups.frames
import qs.features.audio
import "MailParse.js" as Parse

Popup {
    id: root

    popup_name: "mail"
    preferred_width: 320
    footer_hint: "j/k move · gg/G first/last · i inbox · u next unread · r refresh · q close"
    body_height: content.implicitHeight + 24
    jumps_enabled: true
    cursor_state: root.selected
    wheel_steps: true
    onWheel_stepped: (dir, horizontal) => {
        if (!horizontal) root.selected = root.clamp_index(root.selected, dir, 0, root.rows.length);
    }

    // The most rows drawn, so a mailbox with many unread folders cannot outgrow the popup.
    readonly property int max_rows: 12
    readonly property var rows: MailState.counted_folders.slice(0, root.max_rows)
    readonly property int hidden_rows: MailState.counted_folders.length - root.rows.length

    property int selected: 0
    onRowsChanged: if (selected >= rows.length) selected = Math.max(0, rows.length - 1)

    readonly property bool is_open: Popups.open_name === "mail"
    // The folder the headers are for: the one under the cursor.
    readonly property string preview_id: root.is_open && root.rows.length > 0 ? root.rows[Math.min(root.selected, root.rows.length - 1)].id : ""
    onPreview_idChanged: MailPreviewState.show(root.preview_id)
    onIs_openChanged: if (is_open) {
        root.selected = 0;
        MailState.refresh();
    }
    search_enabled: true
    search_rows: root.rows.map(f => f.account + " " + f.path)
    search_cursor: root.selected
    onSearch_select: index => root.selected = index
    onJump_first: root.selected = 0
    onJump_last: root.selected = Math.max(0, root.rows.length - 1)

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: main_column.implicitHeight
        focus: true

        Keys.onPressed: event => {
            const before = root.cursor_key();
            if (event.key === Qt.Key_J) {
                root.selected = root.wrap_index(root.selected, 1, 0, root.rows.length);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = root.wrap_index(root.selected, -1, 0, root.rows.length);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (event.key === Qt.Key_I) {
                ThemeAudio.play("confirm");
                Popups.close();
                MailActions.open_inbox();
                event.accepted = true;
            } else if (event.key === Qt.Key_U) {
                ThemeAudio.play("confirm");
                Popups.close();
                MailActions.next_unread();
                event.accepted = true;
            } else if (event.key === Qt.Key_R) {
                ThemeAudio.play("confirm");
                MailState.refresh();
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 2

            Text {
                visible: root.rows.length === 0
                text: MailState.refused ? MailState.message : "No unread mail"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                textFormat: Text.PlainText
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            Repeater {
                model: root.rows

                MenuRow {
                    id: folder_row
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    height: Style.px(26)
                    selected: folder_row.index === root.selected

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6 + folder_row.inset
                        anchors.rightMargin: 6 + folder_row.key_space
                        spacing: 8

                        RowLabel {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            wrapMode: Text.NoWrap
                            label: folder_row.modelData.path
                            color: folder_row.fg(root.st.text_fg)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-1)
                        }

                        RowLabel {
                            label: folder_row.modelData.account
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            Layout.maximumWidth: 110
                            color: folder_row.fg(root.st.text_dim)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }

                        RowLabel {
                            label: String(folder_row.modelData.unread)
                            color: folder_row.fg(Theme.yellow)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-1)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.selected = folder_row.index
                    }
                }
            }

            // Headers only while the setting is on and nobody can see the screen; `allowed` turns false the moment a recording or share starts.
            ColumnLayout {
                id: preview
                visible: MailPreviewState.allowed && root.rows.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 2

                Text {
                    visible: MailPreviewState.status === "failed"
                    text: "Headers unavailable. Turn on header sharing in DesertBird."
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    color: root.st.text_dim
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                }

                Repeater {
                    model: MailPreviewState.allowed ? MailPreviewState.rows : []

                    ColumnLayout {
                        id: message_row
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            wrapMode: Text.NoWrap
                            text: message_row.modelData.subject || "(no subject)"
                            color: root.st.text_fg
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-2)
                        }

                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            wrapMode: Text.NoWrap
                            text: message_row.modelData.from + "  " + Parse.short_date(message_row.modelData.date, new Date())
                            color: root.st.text_dim
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8

                Repeater {
                    model: [{ label: "Inbox", key: "i" }, { label: "Next unread", key: "u" }]

                    Rectangle {
                        id: action_button
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Style.px(26)
                        radius: 3
                        color: action_area.containsMouse ? Qt.alpha(Theme.yellow, 0.25) : Qt.alpha(root.st.text_dim, 0.12)

                        Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: action_button.modelData.label + " (" + action_button.modelData.key + ")"
                            color: root.st.text_fg
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-2)
                        }

                        MouseArea {
                            id: action_area
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                ThemeAudio.play("confirm");
                                Popups.close();
                                if (action_button.modelData.key === "i") MailActions.open_inbox();
                                else MailActions.next_unread();
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.hidden_rows > 0 || MailState.truncated
                text: root.hidden_rows > 0 ? "and " + root.hidden_rows + " more folders" : "The list was cut short"
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-3)
            }
        }
    }
}
