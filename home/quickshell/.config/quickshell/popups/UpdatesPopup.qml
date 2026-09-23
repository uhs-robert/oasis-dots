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
    preferred_width: 420
    implicitHeight: content.implicitHeight + 24

    readonly property int content_height: 320
    readonly property var sub_names: ["Official (" + UpdatesState.official.length + ")", "AUR (" + UpdatesState.aur.length + ")"]
    readonly property var current_list: root.current_sub === 0 ? UpdatesState.official : UpdatesState.aur

    property int current_sub: 0
    property int selected: 0
    property double last_g_ms: 0

    readonly property bool is_open: Popups.open_name === "updates"
    onIs_openChanged: if (is_open) {
        root.selected = 0;
        UpdatesState.refresh_if_due();
    }

    onCurrent_listChanged: root.selected = Math.max(0, Math.min(root.selected, root.current_list.length - 1))

    function step_sub(delta) {
        root.current_sub = (root.current_sub + delta + root.sub_names.length) % root.sub_names.length;
        root.selected = 0;
    }

    function move_selected(delta) {
        if (root.current_list.length === 0) return;
        root.selected = Math.max(0, Math.min(root.current_list.length - 1, root.selected + delta));
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
        if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            root.step_sub(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Tab) {
            root.step_sub(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_J) {
            root.move_selected(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_K) {
            root.move_selected(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_G) {
            if (event.modifiers & Qt.ShiftModifier) {
                root.go_last();
            } else {
                const now_ms = Date.now();
                if (now_ms - root.last_g_ms < 500) { root.go_first(); root.last_g_ms = 0; }
                else root.last_g_ms = now_ms;
            }
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
        Keys.onTabPressed: event => root.handle_key(event)
        Keys.onBacktabPressed: event => root.handle_key(event)

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
                    color: Theme.fg_core
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    text: UpdatesState.checking ? "Checking…" : UpdatesState.error ? UpdatesState.error : (UpdatesState.last_checked > 0 ? "Checked " + Qt.formatTime(new Date(UpdatesState.last_checked), "HH:mm") : "Never checked")
                    color: UpdatesState.error && !UpdatesState.checking ? Theme.warning : Theme.fg_muted
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size - 3
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.content_height

                Text {
                    anchors.centerIn: parent
                    visible: root.current_list.length === 0
                    text: UpdatesState.error ? UpdatesState.error : "Up to date"
                    color: UpdatesState.error ? Theme.warning : Theme.fg_dim
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size - 1
                }

                ListView {
                    id: row_list
                    anchors.fill: parent
                    visible: root.current_list.length > 0
                    clip: true
                    spacing: 4
                    model: root.current_list
                    currentIndex: root.selected

                    delegate: Rectangle {
                        id: update_row
                        required property var modelData
                        required property int index

                        width: row_list.width
                        height: 30
                        radius: 4
                        color: update_row.index === root.selected ? Theme.bg_surface : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: update_row.modelData.name
                                color: Theme.fg_core
                                font.family: Theme.font_family
                                font.pixelSize: Theme.popup_font_size - 2
                            }

                            Row {
                                Layout.maximumWidth: row_list.width * 0.5
                                spacing: 4

                                Text {
                                    elide: Text.ElideLeft
                                    text: update_row.modelData.old + " →"
                                    color: Theme.fg_muted
                                    font.family: Theme.font_family
                                    font.pixelSize: Theme.popup_font_size - 3
                                }

                                Text {
                                    text: update_row.modelData.new
                                    color: Theme.yellow
                                    font.family: Theme.font_family
                                    font.pixelSize: Theme.popup_font_size - 3
                                }
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
                        model: root.sub_names

                        Rectangle {
                            id: sub_chip
                            required property string modelData
                            required property int index
                            readonly property bool active: sub_chip.index === root.current_sub

                            implicitWidth: sub_label.implicitWidth + 20
                            implicitHeight: 24
                            radius: 12
                            color: sub_chip.active ? Theme.bg_surface : "transparent"

                            Text {
                                id: sub_label
                                anchors.centerIn: parent
                                text: sub_chip.modelData
                                color: sub_chip.active ? Theme.theme_secondary : Theme.fg_muted
                                font.bold: sub_chip.active
                                font.family: Theme.font_family
                                font.pixelSize: Theme.popup_font_size - 3
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.current_sub = sub_chip.index;
                                    root.selected = 0;
                                }
                            }
                        }
                    }
                }
            }

            Text {
                text: "Tab views · j/k move · gg/G first/last · r refresh · u/Enter upgrade · q close"
                color: Theme.fg_dim
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size - 4
            }
        }
    }
}
