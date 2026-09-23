// home/quickshell/.config/quickshell/popups/KeeptabsPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "keeptabs"
    preferred_width: 320
    implicitHeight: content.implicitHeight + 24

    property var sessions: []
    property int selected: 0
    property bool stale: false
    readonly property int max_visible_rows: 8

    readonly property bool is_open: Popups.open_name === "keeptabs"
    onIs_openChanged: if (is_open) {
        root.selected = 0;
        root.refresh();
    }
    onSessionsChanged: selected = Math.max(0, Math.min(selected, sessions.length - 1));

    function refresh() {
        if (!root.is_open) return;
        if (fetch_proc.running) root.stale = true;
        else fetch_proc.running = true;
    }

    // The tooltip lists each session's state, so it changes only when the list does; runs change every animation frame.
    Connections {
        target: KeeptabsState
        function onTooltipChanged() { root.refresh(); }
    }

    Process {
        id: fetch_proc
        command: ["sh", "-c", "exec ~/.local/bin/keeptabs-pick --json"]
        onExited: if (root.stale) {
            root.stale = false;
            root.refresh();
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.sessions = JSON.parse(text);
                } catch (e) {
                    console.warn("keeptabs-pick --json: " + e);
                }
            }
        }
    }

    function state_color(state) {
        if (state === "waiting") return Theme.error;
        if (state === "done") return Theme.ok;
        if (state === "running") return Theme.theme_primary;
        return Theme.fg_dim;
    }

    function age(since) {
        const s = Math.floor(Date.now() / 1000) - since;
        if (s < 60) return s + "s";
        if (s < 3600) return Math.floor(s / 60) + "m";
        return Math.floor(s / 3600) + "h";
    }

    function focus_session(id) {
        Quickshell.execDetached(["sh", "-c", "exec ~/.local/bin/keeptabs-pick --focus \"$1\"", "sh", id]);
        Popups.close();
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
            if (event.key === Qt.Key_J) {
                root.selected = Math.max(0, Math.min(root.sessions.length - 1, root.selected + 1));
                session_list.positionViewAtIndex(root.selected, ListView.Contain);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = Math.max(0, root.selected - 1);
                session_list.positionViewAtIndex(root.selected, ListView.Contain);
                event.accepted = true;
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.sessions[root.selected]) {
                root.focus_session(root.sessions[root.selected].id);
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4

            Text {
                visible: root.sessions.length === 0
                text: "No agent sessions"
                color: Theme.fg_dim
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size - 2
            }

            ListView {
                id: session_list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, root.max_visible_rows * (36 + spacing))
                clip: true
                spacing: 4
                model: root.sessions
                currentIndex: root.selected

                delegate: Rectangle {
                    id: session_row
                    required property var modelData
                    required property int index

                    width: session_list.width
                    height: 36
                    radius: 4
                    color: session_row.index === root.selected ? Theme.bg_surface : "transparent"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        anchors.topMargin: 3
                        anchors.bottomMargin: 3
                        spacing: 1

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: (session_row.modelData.state || "idle").toUpperCase()
                                color: root.state_color(session_row.modelData.state)
                                font.family: Theme.font_family
                                font.pixelSize: Theme.popup_font_size - 2
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: session_row.modelData.title || "Untitled"
                                color: Theme.fg_core
                                font.family: Theme.font_family
                                font.pixelSize: Theme.popup_font_size - 1
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: (session_row.modelData.agent || "claude") + " · " + (session_row.modelData.project || "") + " · " + (session_row.modelData.where || "") + " · " + root.age(session_row.modelData.since)
                            color: Theme.fg_muted
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size - 3
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selected = session_row.index;
                            root.focus_session(session_row.modelData.id);
                        }
                    }
                }
            }
        }
    }
}
