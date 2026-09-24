// home/quickshell/.config/quickshell/popups/VolumePopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "volume"

    WheelStepper {
        id: stepper
    }
    preferred_width: 320
    footer_hint: "j/k move · h/l adjust · m mute · Enter default · q close"
    // The list fits its rows and only scrolls past most of the screen height.
    readonly property real max_list_height: (root.screen ? root.screen.height : 1080) * 0.6
    body_height: content.implicitHeight + 24

    readonly property var output_devices: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var input_devices: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.isSink)

    readonly property var rows: {
        const list = [];
        for (const d of output_devices) list.push({ type: "sink_device", node: d });
        if (Pipewire.defaultAudioSink) list.push({ type: "sink_slider", node: Pipewire.defaultAudioSink });
        for (const d of input_devices) list.push({ type: "source_device", node: d });
        if (Pipewire.defaultAudioSource) list.push({ type: "source_slider", node: Pipewire.defaultAudioSource });
        for (const s of streams) list.push({ type: "stream", node: s });
        return list;
    }

    function section_of(type) {
        if (type === "sink_device" || type === "sink_slider") return "Output";
        if (type === "source_device" || type === "source_slider") return "Input";
        return "Apps";
    }

    function is_slider_row(type) {
        return type !== "sink_device" && type !== "source_device";
    }

    property int selected: 0
    onRowsChanged: if (selected >= rows.length) selected = Math.max(0, rows.length - 1);

    readonly property bool is_open: Popups.open_name === "volume"
    onIs_openChanged: if (is_open) selected = 0

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].filter(o => o).concat(root.streams)
    }

    function adjust(node, delta) {
        if (!node || !node.ready || !node.audio) return;
        node.audio.volume = Math.max(0, Math.min(1, node.audio.volume + delta));
    }

    function adjust_snap(node, direction) {
        if (!node || !node.ready || !node.audio) return;
        const pct = stepper.snap(Math.round(node.audio.volume * 100), direction, 0, 100);
        node.audio.volume = pct / 100;
    }

    function toggle_mute(node) {
        if (!node || !node.audio) return;
        node.audio.muted = !node.audio.muted;
    }

    function set_default(row) {
        if (row.type === "sink_device") Pipewire.preferredDefaultAudioSink = row.node;
        else if (row.type === "source_device") Pipewire.preferredDefaultAudioSource = row.node;
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: main_column.implicitHeight
        focus: true

        Keys.onPressed: event => {
            const row = root.rows[root.selected];
            if (event.key === Qt.Key_J) {
                root.selected = Math.min(root.rows.length - 1, root.selected + 1);
                rows_list.positionViewAtIndex(root.selected, ListView.Contain);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = Math.max(0, root.selected - 1);
                rows_list.positionViewAtIndex(root.selected, ListView.Contain);
                event.accepted = true;
            } else if (event.key === Qt.Key_L && row && root.is_slider_row(row.type)) {
                root.adjust_snap(row.node, 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_H && row && root.is_slider_row(row.type)) {
                root.adjust_snap(row.node, -1);
                event.accepted = true;
            } else if (event.key === Qt.Key_M && row) {
                root.toggle_mute(row.node);
                event.accepted = true;
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && row && !root.is_slider_row(row.type)) {
                root.set_default(row);
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 2

            ListView {
                id: rows_list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, root.max_list_height)
                clip: true
                spacing: 2
                model: root.rows
                currentIndex: root.selected

                delegate: Column {
                    id: row_wrap
                    required property var modelData
                    required property int index

                    width: rows_list.width
                    spacing: 2

                    MenuSection {
                        visible: row_wrap.index === 0 || root.section_of(root.rows[row_wrap.index - 1].type) !== root.section_of(row_wrap.modelData.type)
                        topPadding: row_wrap.index === 0 ? 0 : 6
                        label: root.section_of(row_wrap.modelData.type)
                    }

                    MenuRow {
                        id: vol_row
                        width: row_wrap.width
                        height: Style.px(22)
                        selected: row_wrap.index === root.selected

                        RowLayout {
                            visible: !root.is_slider_row(row_wrap.modelData.type)
                            anchors.fill: parent
                            anchors.leftMargin: 6 + vol_row.inset
                            anchors.rightMargin: 6
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: row_wrap.modelData.node.description || row_wrap.modelData.node.name
                                color: vol_row.fg((row_wrap.modelData.node === Pipewire.defaultAudioSink || row_wrap.modelData.node === Pipewire.defaultAudioSource) ? Theme.theme_secondary : Theme.fg_core)
                                font.family: Style.font_family
                                font.pixelSize: Style.font_size - 1
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.is_slider_row(row_wrap.modelData.type)
                            onClicked: {
                                root.selected = row_wrap.index;
                                root.set_default(row_wrap.modelData);
                            }
                        }

                        RowLayout {
                            visible: root.is_slider_row(row_wrap.modelData.type)
                            anchors.fill: parent
                            anchors.leftMargin: 6 + vol_row.inset
                            anchors.rightMargin: 6
                            spacing: 6

                            Text {
                                Layout.preferredWidth: Style.px(90)
                                elide: Text.ElideRight
                                text: row_wrap.modelData.type === "stream" ? (row_wrap.modelData.node.properties["application.name"] || row_wrap.modelData.node.name) : (row_wrap.modelData.node.description || row_wrap.modelData.node.name)
                                color: vol_row.fg(Theme.fg_core)
                                font.family: Style.font_family
                                font.pixelSize: Style.font_size - 1
                            }

                            Slider {
                                Layout.fillWidth: true
                                on_selection: vol_row.selected
                                value: row_wrap.modelData.node.audio ? row_wrap.modelData.node.audio.volume : 0
                                onMoved: v => {
                                    if (row_wrap.modelData.node.audio) row_wrap.modelData.node.audio.volume = v;
                                }
                            }

                            Text {
                                text: row_wrap.modelData.node.audio && row_wrap.modelData.node.audio.muted ? "" : ""
                                color: vol_row.fg(Theme.theme_primary)
                                font.family: Style.font_family
                                font.pixelSize: Style.font_size - 1

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.toggle_mute(row_wrap.modelData.node)
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.streams.length === 0
                Layout.topMargin: 6
                text: "No apps playing"
                color: Theme.fg_dim
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 2
            }
        }
    }
}
