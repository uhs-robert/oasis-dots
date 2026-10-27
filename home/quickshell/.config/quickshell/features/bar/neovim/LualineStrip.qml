import QtQuick
import QtQuick.Shapes
import qs.core
import qs.theme
import qs.features.bar
import qs.features.media
import qs.features.popups
import "../BarLayout.js" as BarLayout

// The Bar-owned parts of NeoVim's lualine statusline, along one edge from `start` to `end`: section c's fill, the
// window segment and cava slot inside it, and the x, y and z sections (`sections`). The mode chip and buffer tabs
// (sections a and b) stay in the left island's modules, so the strip reads both islands for where c begins and ends.
Item {
    id: root

    property bool active: true
    // "top" or "bottom": a bottom strip draws its cava upside down.
    property string edge: "top"
    // Along-edge extent, in the parent's coordinates.
    property real start: 0
    property real end: 0
    property real bar_height: 24
    property string screen_name: ""
    // Islands hold the a/b modules and the x/y/z sections, so the strip follows them rather than owning them.
    property Island left_island: null
    property Island right_island: null
    // The cava module is listed in bars.json.
    property bool lists_cava: false
    property var lualine_entries: []
    property var module_props: ({})
    // Called with (item, entry) to wire a loaded module; the Bar owns that wiring.
    property var wire: null
    // Instantiate inside the right island's layout.
    readonly property Component sections: sections_component

    readonly property bool left_shown: !!root.left_island && root.left_island.visible
    readonly property bool right_shown: !!root.right_island && root.right_island.visible
    // Section c, in strip coordinates: from the left island's end to the right island's cap.
    readonly property real c_start: root.left_shown ? root.left_island.x + root.left_island.width - root.start : 0
    readonly property real c_end: (root.right_shown ? root.right_island.x : root.end) - root.start
    readonly property real section_c: root.c_end - root.c_start

    x: root.start
    width: Math.max(0, root.end - root.start)
    height: root.bar_height
    visible: root.active

    Rectangle {
        visible: !Style.islands_translucent
        width: root.width
        height: root.bar_height
        color: Theme.bg_mantle
    }

    // Translucent, section c fills only between the islands, beside their arrow caps, so no fill stacks on it.
    Shape {
        visible: Style.islands_translucent
        width: root.width
        height: root.bar_height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Style.island_fill(Theme.bg_mantle)
            PathPolyline {
                path: {
                    const h = root.bar_height;
                    const l = root.c_start, lc = root.left_shown ? root.left_island.cap_width : 0;
                    const r = root.c_end, rc = root.right_shown ? root.right_island.cap_width : 0;
                    return [Qt.point(l - lc, 0), Qt.point(r + rc, 0), Qt.point(r, h / 2), Qt.point(r + rc, h), Qt.point(l - lc, h), Qt.point(l, h / 2), Qt.point(l - lc, 0)];
                }
            }
        }
    }

    // After the buffers: the focused app and a terminal's directory.
    Loader {
        id: segment_loader
        active: root.active && root.left_shown
        x: root.c_start
        sourceComponent: WindowSegment {
            screen_name: root.screen_name
            bar_height: root.bar_height
            max_width: Math.max(0, root.section_c - 8 - (cava_slot.shown ? cava_slot.width + 16 : 0))
        }
    }

    // Lualine has no center island: cava plays at the end of section c, left of the right island's cap,
    // in whatever room the window segment's minimum leaves; under 48px it hides on this screen.
    Item {
        id: cava_slot
        readonly property real room: root.section_c - (segment_loader.item ? segment_loader.item.min_width : 0) - 16
        readonly property bool shown: root.active && root.lists_cava && root.right_shown && MediaState.playing && PowerSource.on_ac && cava_slot.room >= 48
        visible: cava_slot.shown
        x: root.c_end - width - 8
        width: Math.max(0, Math.min(120, cava_slot.room))
        height: root.bar_height

        CavaViewer { active: cava_slot.shown }

        CavaBars {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            height: parent.height - 6
            flipped: root.edge === "bottom"
            active: cava_slot.shown
        }

        // The three members HoverPopup reads from a module; the slot reuses the media popup, so it has no popup of its own.
        readonly property Item island: root.right_island.body_item
        readonly property color island_color: root.right_island.bg_color
        readonly property string screen_name: root.screen_name
        readonly property bool hovered: slot_hover.hovered

        HoverHandler {
            id: slot_hover
        }

        HoverPopup {
            id: slot_popup
            popup_name: "media"
            module: cava_slot
            enabled: cava_slot.shown
        }

        // The Media module's own helper can pin the popup this one hover-opened, and this one's pending close would then shut it. That shows as the owner dropping with the popup still open; a close or another popup's open drops it too but changes open_name in the same call, so look after the call.
        Connections {
            target: Popups
            function onHover_ownerChanged() {
                if (slot_popup.mode === "hover_open") Qt.callLater(cava_slot.take_pin);
            }
        }

        function take_pin() {
            if (slot_popup.mode === "hover_open" && !Popups.hover_owner && slot_popup.open_here) Popups.popup_pressed(slot_popup.popup_name);
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                slot_popup.click();
                // A click pins, but Media's helper may have hover-opened this popup and would close it after its grace.
                Popups.popup_pressed(slot_popup.popup_name);
            }
        }
    }

    Component {
        id: sections_component

        Row {
            readonly property var wire: (item, entry) => root.wire(item, entry)
            // The sections draw their own fills, so a translucent island leaves its colour out from behind them.
            readonly property bool lualine_fill: true

            LualineSection {
                id: x_section
                height: root.right_island.height
                entries: root.lualine_entries.filter(e => BarLayout.lualine_section(e.base) === "x")
                wire: parent.wire
                module_props: root.module_props
                fill: Theme.bg_mantle
                screen_name: root.screen_name
            }

            LualineSection {
                id: y_section
                height: root.right_island.height
                entries: root.lualine_entries.filter(e => BarLayout.lualine_section(e.base) === "y")
                wire: parent.wire
                module_props: root.module_props
                fill: Theme.ui_visual_bg
                hover_fill: Qt.tint(Theme.ui_visual_bg, Qt.alpha(Theme.theme_primary, 0.3))
                lead_bg: x_section.shown ? x_section.end_fill : "transparent"
                separators: false
            }

            LualineSection {
                height: root.right_island.height
                entries: root.lualine_entries.filter(e => BarLayout.lualine_section(e.base) === "z")
                wire: parent.wire
                module_props: root.module_props
                fill: SubmapState.bar_color
                accent: true
                // The mode chip's hover tint.
                hover_fill: Qt.tint(fill, Qt.alpha(Theme.fg_strong, 0.15))
                separators: false
                lead_bg: y_section.shown ? y_section.end_fill : x_section.shown ? x_section.end_fill : "transparent"
            }
        }
    }
}
