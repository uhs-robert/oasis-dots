// home/quickshell/.config/quickshell/bar/Bar.qml
import QtQuick
import "../theme"
import "../services"
import "modules"

Item {
    id: root

    property string screen_name: ""
    property var rule: null
    readonly property bool compact: BarConfig.compact_for(root.rule, root.screen_name)
    readonly property real center_width: center_island.body_item.width

    readonly property var module_map: ({
        start: start_component,
        workspaces: workspaces_component,
        clock: clock_component,
        tray: tray_component,
        volume: volume_component,
        battery: battery_component,
        bluetooth: bluetooth_component,
        system: system_component,
        network: network_component,
        weather: weather_component,
        keeptabs: keeptabs_component,
        voxtype: voxtype_component,
        notifications: notifications_component
    })

    // Resolves a bars.json module list into loadable entries, skipping unknown names.
    function build_entries(names) {
        const list = [];
        for (const raw of names || []) {
            const parsed = BarConfig.parse_module(raw);
            const component = root.module_map[parsed.base];
            if (!component) {
                BarConfig.warn_unknown_module(parsed.base);
                continue;
            }
            list.push({ base: parsed.base, arg: parsed.arg, component: component });
        }
        return list;
    }

    readonly property var left_entries: root.build_entries(root.rule ? root.rule.left : [])
    readonly property var center_entries: root.build_entries(root.rule ? root.rule.center : [])
    readonly property var right_entries: root.build_entries(root.rule ? root.rule.right : [])

    // Sets island/screen/stat properties a module declares, after the Loader instantiates it.
    function wire_module(item, entry, island) {
        // Color first: setting island triggers the module's popup registration, which reads it.
        if (item.hasOwnProperty("island_color")) item.island_color = Qt.binding(() => island.bg_color);
        if (item.hasOwnProperty("island")) item.island = island.body_item;
        if (entry.arg && item.hasOwnProperty("stat")) item.stat = entry.arg;
    }

    Component { id: start_component; StartButton { compact: root.compact; screen_name: root.screen_name } }
    Component { id: workspaces_component; Workspaces { compact: root.compact; screen_name: root.screen_name } }
    Component { id: clock_component; Clock { compact: root.compact } }
    Component { id: tray_component; Tray { compact: root.compact; screen_name: root.screen_name } }
    Component { id: volume_component; Volume { compact: root.compact; screen_name: root.screen_name } }
    Component { id: battery_component; Battery { compact: root.compact; screen_name: root.screen_name } }
    Component { id: bluetooth_component; Bluetooth { compact: root.compact; screen_name: root.screen_name } }
    Component { id: system_component; System { compact: root.compact; screen_name: root.screen_name } }
    Component { id: network_component; Network { screen_name: root.screen_name } }
    Component { id: weather_component; Placeholder { glyph: "\u{f0f31}"; label: "--\u00b0"; tooltip_text: "Weather (coming soon)" } }
    Component { id: keeptabs_component; Keeptabs { compact: root.compact } }
    Component { id: voxtype_component; Voxtype { compact: root.compact } }
    Component { id: notifications_component; Placeholder { glyph: "\u{f009a}"; tooltip_text: "Notifications (coming soon)" } }

    Island {
        id: left_island
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Theme.bg_core
        cap_right: true
        visible: root.left_entries.length > 0

        onClicked: if (root.left_entries.some(e => e.base === "clock")) Popups.toggle("clock", left_island.body_item, left_island.bg_color, root.screen_name)

        Repeater {
            model: root.left_entries

            Loader {
                required property var modelData
                sourceComponent: modelData.component
                // A module that hides itself must also leave the RowLayout, or its spacing remains.
                visible: !item || item.visible
                onLoaded: root.wire_module(item, modelData, left_island)
            }
        }
    }

    Island {
        id: center_island
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Theme.bg_mantle
        cap_left: true
        cap_right: true
        visible: root.center_entries.length > 0

        onClicked: if (root.center_entries.some(e => e.base === "clock")) Popups.toggle("clock", center_island.body_item, center_island.bg_color, root.screen_name)

        Repeater {
            model: root.center_entries

            Loader {
                required property var modelData
                sourceComponent: modelData.component
                // A module that hides itself must also leave the RowLayout, or its spacing remains.
                visible: !item || item.visible
                onLoaded: root.wire_module(item, modelData, center_island)
            }
        }
    }

    Island {
        id: right_island
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Theme.bg_core
        cap_left: true
        visible: root.right_entries.length > 0

        onClicked: if (root.right_entries.some(e => e.base === "clock")) Popups.toggle("clock", right_island.body_item, right_island.bg_color, root.screen_name)

        Repeater {
            model: root.right_entries

            Loader {
                required property var modelData
                sourceComponent: modelData.component
                // A module that hides itself must also leave the RowLayout, or its spacing remains.
                visible: !item || item.visible
                onLoaded: root.wire_module(item, modelData, right_island)
            }
        }
    }

    // The clock has no module item of its own, so its popup anchor follows whichever island lists it.
    function sync_clock_anchor() {
        const has_clock = entries => entries.some(e => e.base === "clock");
        const island = has_clock(root.left_entries) ? left_island : has_clock(root.center_entries) ? center_island : has_clock(root.right_entries) ? right_island : null;
        for (const i of [left_island, center_island, right_island]) Popups.unregister("clock", root.screen_name, i.body_item);
        if (island) Popups.register_default("clock", island.body_item, island.bg_color, root.screen_name);
    }

    onLeft_entriesChanged: sync_clock_anchor()
    onCenter_entriesChanged: sync_clock_anchor()
    onRight_entriesChanged: sync_clock_anchor()
    Component.onCompleted: sync_clock_anchor()
    Component.onDestruction: Popups.unregister_screen(root.screen_name)
}
