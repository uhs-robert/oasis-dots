// home/quickshell/.config/quickshell/popups/UpdatesPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../theme"
import "../services"
import "updates" as Updates
import "snes" as Snes
import "../components/ps1" as Ps1
import "../components/ps2" as Ps2

Popup {
    id: root

    popup_name: "updates"
    preferred_width: 520
    fit_island: true
    body_height: content.implicitHeight + 24
    key_help: "Tab views · j/k move · gg/G ends · r refresh · u upgrade · q close"

    readonly property int content_height: Style.px(320)
    readonly property bool nes: root.st.console_views === "nes"
    sub_views: root.nes ? ["Official x" + UpdatesState.official.length, "AUR x" + UpdatesState.aur.length] : ["Official (" + UpdatesState.official.length + ")", "AUR (" + UpdatesState.aur.length + ")"]
    jumps_enabled: true
    readonly property var current_list: root.current_sub === 0 ? UpdatesState.official : UpdatesState.aur

    property int selected: 0

    function reveal(index) {
        if (list_view.item && list_view.item.reveal) list_view.item.reveal(index);
        else row_list.positionViewAtIndex(index, ListView.Contain);
    }
    readonly property bool ps2: root.st.console_views === "ps2"

    readonly property bool is_open: Popups.open_name === "updates"
    onIs_openChanged: if (is_open) {
        root.selected = 0;
        UpdatesState.refresh_if_due();
    }

    onCurrent_listChanged: root.selected = Math.max(0, Math.min(root.selected, root.current_list.length - 1))
    onCurrent_subChanged: root.selected = 0
    search_enabled: true
    search_rows: root.current_list.map(p => p.name)
    search_cursor: root.selected
    onSearch_select: index => {
        root.selected = index;
        root.reveal(index);
    }
    onJump_first: root.go_first()
    onJump_last: root.go_last()

    function move_selected(delta) {
        if (root.current_list.length === 0) return;
        root.selected = root.wrap_index(root.selected, delta, 0, root.current_list.length);
        root.reveal(root.selected);
    }

    function go_first() {
        root.selected = 0;
        root.reveal(root.selected);
    }

    function go_last() {
        root.selected = Math.max(0, root.current_list.length - 1);
        root.reveal(root.selected);
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

            Loader {
                active: root.ps2
                visible: active
                Layout.fillWidth: true
                sourceComponent: Row {
                    spacing: 8

                    Text {
                        text: UpdatesState.total
                        color: Theme.fg_strong
                        font.family: root.st.font_family
                        font.pixelSize: root.st.font_size * 2
                        font.weight: Font.ExtraLight
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Text {
                            text: UpdatesState.total === 1 ? "block" : "blocks"
                            color: Theme.theme_primary_light
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-4)
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.2
                        }

                        Text {
                            text: UpdatesState.official.length + " official · " + UpdatesState.aur.length + " AUR"
                            color: root.st.text_muted
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-4)
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    visible: !root.ps2
                    width: Math.min(implicitWidth, parent.width)
                    text: root.nes ? "UPDATES x" + UpdatesState.total : UpdatesState.total + " update" + (UpdatesState.total === 1 ? "" : "s") + " · " + UpdatesState.official.length + " official, " + UpdatesState.aur.length + " AUR"
                    color: root.st.text_fg
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.min(implicitWidth, parent.width)
                    elide: Text.ElideRight
                    text: UpdatesState.checking ? "Checking…" : UpdatesState.error ? UpdatesState.error : (UpdatesState.last_checked > 0 ? "Checked " + Qt.formatTime(new Date(UpdatesState.last_checked), "HH:mm") : "Never checked")
                    color: UpdatesState.error && !UpdatesState.checking ? Theme.warning : root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.content_height

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 16
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: root.current_list.length === 0
                    text: UpdatesState.error ? UpdatesState.error : "Up to date"
                    color: UpdatesState.error ? Theme.warning : root.st.text_dim
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-1)
                }

                // Console grids replace the package list.
                Loader {
                    id: list_view
                    anchors.fill: parent
                    readonly property Component view: ({ nes: nes_inventory, snes: snes_inventory, ps1: ps1_blocks })[root.st.console_views] || null
                    active: !!view && root.current_list.length > 0
                    visible: active
                    sourceComponent: view
                }

                Component {
                    id: nes_inventory
                    Updates.NesInventory {
                        popup: root
                    }
                }

                Component {
                    id: snes_inventory
                    Snes.SnesInventory {
                        items: root.current_list
                        selected: root.selected
                        aur: root.current_sub === 1
                        onClicked: index => root.selected = index
                    }
                }

                Component {
                    id: ps1_blocks
                    Ps1.UpdateBlocks {
                        packages: root.current_list
                        selected: root.selected
                        onPicked: index => root.selected = index
                    }
                }

                ListView {
                    id: row_list
                    anchors.fill: parent
                    visible: root.current_list.length > 0 && !list_view.active
                    clip: true
                    spacing: 4
                    model: root.current_list
                    currentIndex: root.selected

                    // Rows too narrow for a typical name beside its versions put the versions on a second line.
                    readonly property bool stacked: row_list.width < row_metrics.advanceWidth("python-package-name 1.23.4-1 → 1.23.5-1") + 24 + (root.ps2 ? Style.px(20) + 10 : 0)

                    FontMetrics {
                        id: row_metrics
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-2)
                    }

                    delegate: MenuRow {
                        id: update_row
                        required property var modelData
                        required property int index

                        width: row_list.width
                        height: row_list.stacked ? Math.max(Style.px(30), row_text.implicitHeight + 8) : Style.px(30)
                        selected: update_row.index === root.selected

                        Loader {
                            id: save_icon
                            active: root.ps2
                            x: 8 + update_row.inset
                            anchors.verticalCenter: parent.verticalCenter
                            sourceComponent: Ps2.SaveCube {
                                width: Style.px(20)
                                letter: update_row.modelData.name.charAt(0)
                                color: root.current_sub === 0 ? Theme.theme_primary : Theme.theme_secondary_strong
                                selected: update_row.selected
                            }
                        }

                        GridLayout {
                            id: row_text
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 8 + update_row.inset + (save_icon.active ? save_icon.width + 10 : 0)
                            anchors.rightMargin: 8 + update_row.key_space
                            columns: row_list.stacked ? 1 : 2
                            columnSpacing: 8
                            rowSpacing: 0

                            RowLabel {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                label: update_row.modelData.name
                                color: update_row.fg(root.st.text_fg)
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-2)
                            }

                            // One elided Text so long versions shrink from the left and keep the new version visible.
                            Text {
                                Layout.fillWidth: row_list.stacked
                                Layout.maximumWidth: row_list.stacked ? row_text.width - 8 : row_list.width * 0.6
                                Layout.leftMargin: row_list.stacked ? 8 : 0
                                elide: Text.ElideLeft
                                textFormat: Text.StyledText
                                text: update_row.modelData.old + " → <font color=\"" + Theme.yellow + "\">" + update_row.modelData.new + "</font>"
                                color: update_row.fg(root.st.text_muted)
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-3)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selected = update_row.index
                        }
                    }
                }
            }

            TabRows {
                Layout.fillWidth: true
                chips: true
                labels: root.sub_views
                current: root.current_sub
                onPicked: index => {
                    root.current_sub = index;
                    root.selected = 0;
                }
            }

            MenuFooter {
                Layout.fillWidth: true
                wrap: true
                text: root.help_hint
            }
        }
    }
}
