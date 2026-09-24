// home/quickshell/.config/quickshell/popups/UpdatesPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "updates"
    preferred_width: 520
    body_height: content.implicitHeight + 24
    key_help: "Tab views · j/k move · gg/G ends · r refresh · u upgrade · q close"

    readonly property int content_height: Style.px(320)
    sub_views: ["Official (" + UpdatesState.official.length + ")", "AUR (" + UpdatesState.aur.length + ")"]
    jumps_enabled: true
    readonly property var current_list: root.current_sub === 0 ? UpdatesState.official : UpdatesState.aur

    property int selected: 0

    readonly property bool is_open: Popups.open_name === "updates"
    onIs_openChanged: if (is_open) {
        root.selected = 0;
        UpdatesState.refresh_if_due();
    }

    onCurrent_listChanged: root.selected = Math.max(0, Math.min(root.selected, root.current_list.length - 1))
    onCurrent_subChanged: root.selected = 0
    onJump_first: root.go_first()
    onJump_last: root.go_last()

    function move_selected(delta) {
        if (root.current_list.length === 0) return;
        root.selected = root.wrap_index(root.selected, delta, 0, root.current_list.length);
        row_list.positionViewAtIndex(root.selected, ListView.Contain);
    }

    function go_first() {
        root.selected = 0;
        row_list.positionViewAtIndex(root.selected, ListView.Contain);
    }

    function go_last() {
        root.selected = Math.max(0, root.current_list.length - 1);
        row_list.positionViewAtIndex(root.selected, ListView.Contain);
    }

    function run_selected_upgrade() {
        UpdatesState.run_upgrade();
        Popups.close();
    }

    function handle_key(event) {
        if (event.key === Qt.Key_J) {
            root.move_selected(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_K) {
            root.move_selected(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_R) {
            UpdatesState.refresh();
            event.accepted = true;
        } else if (event.key === Qt.Key_U || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.run_selected_upgrade();
            event.accepted = true;
        }
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: main_column.implicitHeight
        focus: true

        Keys.onPressed: event => root.handle_key(event)

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: UpdatesState.total + " update" + (UpdatesState.total === 1 ? "" : "s") + " · " + UpdatesState.official.length + " official, " + UpdatesState.aur.length + " AUR"
                    color: root.st.text_fg
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    text: UpdatesState.checking ? "Checking…" : UpdatesState.error ? UpdatesState.error : (UpdatesState.last_checked > 0 ? "Checked " + Qt.formatTime(new Date(UpdatesState.last_checked), "HH:mm") : "Never checked")
                    color: UpdatesState.error && !UpdatesState.checking ? Theme.warning : root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 3
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.content_height

                Text {
                    anchors.centerIn: parent
                    visible: root.current_list.length === 0
                    text: UpdatesState.error ? UpdatesState.error : "Up to date"
                    color: UpdatesState.error ? Theme.warning : root.st.text_dim
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 1
                }

                ListView {
                    id: row_list
                    anchors.fill: parent
                    visible: root.current_list.length > 0
                    clip: true
                    spacing: 4
                    model: root.current_list
                    currentIndex: root.selected

                    delegate: MenuRow {
                        id: update_row
                        required property var modelData
                        required property int index

                        width: row_list.width
                        height: Style.px(30)
                        selected: update_row.index === root.selected

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8 + update_row.inset
                            anchors.rightMargin: 8 + update_row.key_space
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                text: update_row.modelData.name
                                color: update_row.fg(root.st.text_fg)
                                font.family: root.st.font_family
                                font.pixelSize: root.st.font_size - 2
                            }

                            // One elided Text so long versions shrink from the left and keep the new version visible.
                            Text {
                                Layout.maximumWidth: row_list.width * 0.6
                                elide: Text.ElideLeft
                                textFormat: Text.StyledText
                                text: update_row.modelData.old + " → <font color=\"" + Theme.yellow + "\">" + update_row.modelData.new + "</font>"
                                color: update_row.fg(root.st.text_muted)
                                font.family: root.st.font_family
                                font.pixelSize: root.st.font_size - 3
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selected = update_row.index
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 28

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: root.sub_views

                        MenuTab {
                            id: sub_chip
                            required property string modelData
                            required property int index

                            base_radius: 12
                            label: sub_chip.modelData
                            active: sub_chip.index === root.current_sub
                            font_size: root.st.font_size - 3
                            onClicked: {
                                root.current_sub = sub_chip.index;
                                root.selected = 0;
                            }
                        }
                    }
                }
            }

            MenuFooter {
                Layout.fillWidth: true
                text: root.help_hint
            }
        }
    }
}
