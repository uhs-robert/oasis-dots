// home/quickshell/.config/quickshell/bar/Bar.qml
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"
import "modules"

Item {
    id: root

    property string screen_name: ""
    property var rule: null
    readonly property bool compact: BarConfig.compact_for(root.rule, root.screen_name)
    readonly property int bar_height: BarConfig.height_for(root.rule)
    readonly property real center_width: center_island.body_item.width
    readonly property bool has_center: root.center_entries.length > 0

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
        updates: updates_component,
        voxtype: voxtype_component,
        notifications: notifications_component,
        media: media_component
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
    Component { id: weather_component; Weather { compact: root.compact; screen_name: root.screen_name } }
    Component { id: keeptabs_component; Keeptabs { compact: root.compact; screen_name: root.screen_name } }
    Component { id: updates_component; Updates { compact: root.compact; screen_name: root.screen_name } }
    Component { id: voxtype_component; Voxtype { compact: root.compact } }
    Component { id: notifications_component; Notifications { compact: root.compact; screen_name: root.screen_name } }
    Component { id: media_component; Media { compact: root.compact; screen_name: root.screen_name } }

    Island {
        height: root.bar_height
        id: left_island
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Style.bar_side_bg
        border_width: Style.bar_border_width
        border_color: Style.bar_border_color
        scanline_color: Style.bar_scanline_color
        shade_color: Style.frame_shade
        shade_vertical: Style.shade_vertical
        dither_color: Qt.alpha(Style.dither, Math.min(1, Style.dither.a * 2.2))
        inset_gap: Style.bar_inset_gap
        inset_width: Style.bar_inset_width
        inset_color: Style.bar_inset_color
        visor: Style.frame_visor
        cap_right: true
        visible: root.left_entries.length > 0

        onClicked: if (root.left_entries.some(e => e.base === "clock")) Popups.toggle("clock", left_island.body_item, left_island.bg_color, root.screen_name)

        Repeater {
            model: root.left_entries

            Loader {
                required property var modelData
                sourceComponent: modelData.component
                // Reads the module's own `shown`, not `visible`: a hidden Loader would report its child hidden too.
                visible: !item || item.shown === undefined || item.shown
                // Keeps the start button close to the workspace pills it launches into.
                Layout.rightMargin: modelData.base === "start" ? -8 : 0
                onLoaded: root.wire_module(item, modelData, left_island)
            }
        }
    }

    Island {
        height: root.bar_height
        id: center_island
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Style.bar_center_bg
        border_width: Style.bar_border_width
        border_color: Style.bar_border_color
        scanline_color: Style.bar_scanline_color
        shade_color: Style.frame_shade
        shade_vertical: Style.shade_vertical
        dither_color: Qt.alpha(Style.dither, Math.min(1, Style.dither.a * 2.2))
        inset_gap: Style.bar_inset_gap
        inset_width: Style.bar_inset_width
        inset_color: Style.bar_inset_color
        visor: Style.frame_visor
        cap_left: true
        cap_right: true
        visible: root.center_entries.length > 0

        onClicked: if (root.center_entries.some(e => e.base === "clock")) Popups.toggle("clock", center_island.body_item, center_island.bg_color, root.screen_name)

        Repeater {
            model: root.center_entries

            Loader {
                required property var modelData
                sourceComponent: modelData.component
                // Reads the module's own `shown`, not `visible`: a hidden Loader would report its child hidden too.
                visible: !item || item.shown === undefined || item.shown
                onLoaded: root.wire_module(item, modelData, center_island)
            }
        }
    }

    CavaBars {
        parent: center_island.body_item
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        anchors.bottomMargin: center_island.inset_color.a > 0 ? center_island.inset_gap + center_island.inset_width : 0
        active: MediaState.playing && root.has_center
    }

    Island {
        height: root.bar_height
        id: right_island
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        bg_color: Style.bar_side_bg
        border_width: Style.bar_border_width
        border_color: Style.bar_border_color
        scanline_color: Style.bar_scanline_color
        shade_color: Style.frame_shade
        shade_vertical: Style.shade_vertical
        dither_color: Qt.alpha(Style.dither, Math.min(1, Style.dither.a * 2.2))
        inset_gap: Style.bar_inset_gap
        inset_width: Style.bar_inset_width
        inset_color: Style.bar_inset_color
        visor: Style.frame_visor
        cap_left: true
        visible: root.right_entries.length > 0

        onClicked: if (root.right_entries.some(e => e.base === "clock")) Popups.toggle("clock", right_island.body_item, right_island.bg_color, root.screen_name)

        Repeater {
            model: root.right_entries

            Loader {
                required property var modelData
                sourceComponent: modelData.component
                // Reads the module's own `shown`, not `visible`: a hidden Loader would report its child hidden too.
                visible: !item || item.shown === undefined || item.shown
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
        // Without a media module in bars.json, the media popup drops from the center island.
        Popups.unregister("media", root.screen_name, center_island.body_item);
        const has_media = [root.left_entries, root.center_entries, root.right_entries].some(l => l.some(e => e.base === "media"));
        if (root.has_center && !has_media) Popups.register_default("media", center_island.body_item, center_island.bg_color, root.screen_name);
    }

    onLeft_entriesChanged: sync_clock_anchor()
    onCenter_entriesChanged: sync_clock_anchor()
    onRight_entriesChanged: sync_clock_anchor()
    Component.onCompleted: sync_clock_anchor()
    Component.onDestruction: Popups.unregister_screen(root.screen_name)
}
