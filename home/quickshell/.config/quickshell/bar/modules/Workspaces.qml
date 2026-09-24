// home/quickshell/.config/quickshell/bar/modules/Workspaces.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../../theme"
import "../../services"

Item {
    id: root

    property string screen_name: ""
    property bool compact: false

    readonly property int icon_size: compact ? 16 : 19
    readonly property int pill_height: compact ? 20 : 22

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    readonly property var workspace_list: {
        const list = Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor && w.monitor.name === root.screen_name);
        list.sort((a, b) => a.id - b.id);
        return list;
    }

    function icon_for(cls) {
        const entry = DesktopEntries.heuristicLookup(cls);
        return Quickshell.iconPath(entry ? entry.icon : cls, "application-x-executable");
    }

    function class_of(toplevel) {
        if (toplevel.wayland && toplevel.wayland.appId) return toplevel.wayland.appId;
        return (toplevel.lastIpcObject && toplevel.lastIpcObject.class) || "";
    }

    // Mirrors hypr-focus-workspaces.lua: focus the workspace then the window, holding cursor:no_warps.
    function focus_toplevel(ws_id, address) {
        Hyprland.dispatch("hl.dsp.focus({ workspace = '" + ws_id + "' })");
        const cmd = "already=$(hyprctl getoption cursor:no_warps -j | grep -o '\"bool\": *true'); " +
            "if [ -z \"$already\" ]; then hyprctl eval \"hl.config({ cursor = { no_warps = true } })\" >/dev/null 2>&1; fi; " +
            "hyprctl dispatch \"hl.dsp.focus({ window = 'address:0x" + address + "' })\"; " +
            "if [ -z \"$already\" ]; then hyprctl eval \"hl.config({ cursor = { no_warps = false } })\" >/dev/null 2>&1; fi";
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    function close_toplevel(address) {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.close({ window = 'address:0x" + address + "' })"]);
    }

    // The workspace/toplevel models can lag behind these events; nudge a resync.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (["openwindow", "closewindow", "movewindow", "workspace", "focusedmon"].includes(event.name)) {
                Hyprland.refreshToplevels();
                Hyprland.refreshWorkspaces();
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            Hyprland.dispatch("hl.dsp.focus({ workspace = '" + (wheel.angleDelta.y > 0 ? "e-1" : "e+1") + "' })");
        }
    }

    Row {
        id: row
        spacing: root.compact ? 6 : 8

        Repeater {
            model: root.workspace_list

            Rectangle {
                id: pill
                required property var modelData

                readonly property bool is_empty: modelData.toplevels.values.length === 0

                height: root.pill_height
                width: is_empty ? height : icons.implicitWidth + (modelData.active ? 22 : 12)
                radius: height / 2
                color: modelData.focused ? Style.bar_workspace_focused : modelData.active ? Style.bar_workspace_active : Style.bar_workspace_idle
                border.width: Style.bar_workspace_ring.a > 0 ? 1 : 0
                border.color: Style.bar_workspace_ring

                Behavior on width {
                    NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
                }
                Behavior on color {
                    ColorAnimation { duration: 280; easing.type: Easing.InOutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Theme.fg_core
                    opacity: !pill.modelData.active && pill_hover.hovered ? 0.1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = '" + pill.modelData.id + "' })")
                }

                HoverHandler {
                    id: pill_hover
                }

                Row {
                    id: icons
                    anchors.centerIn: parent
                    spacing: 2

                    Repeater {
                        model: pill.modelData.toplevels.values

                        Item {
                            id: icon_item
                            required property var modelData

                            width: root.icon_size + 4
                            height: root.icon_size + 4

                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: root.icon_size
                                source: root.icon_for(root.class_of(icon_item.modelData))
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.LeftButton) {
                                        root.focus_toplevel(pill.modelData.id, icon_item.modelData.address);
                                    } else if (mouse.button === Qt.MiddleButton) {
                                        root.close_toplevel(icon_item.modelData.address);
                                    }
                                }
                            }

                            HoverHandler {
                                onHoveredChanged: {
                                    if (hovered) Tooltip.show(icon_item, icon_item.modelData.title);
                                    else Tooltip.hide();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
