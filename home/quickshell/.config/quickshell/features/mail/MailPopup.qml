import QtQuick
import QtQuick.Layouts
import qs.ui.menu
import qs.theme
import qs.features.popups
import qs.features.popups.frames
import qs.features.audio

Popup {
    id: root

    popup_name: "mail"
    preferred_width: 320
    footer_hint: "j/k move · gg/G first/last · r refresh · q close"
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
