import QtQuick
import QtQuick.Layouts
import qs.ui.menu
import qs.theme
import qs.features.popups
import qs.features.popups.frames
import qs.features.audio
import qs.features.bar
import "Sections.js" as Sections

Popup {
    id: root
    hold_keyboard: true

    popup_name: "settings"
    title: "SETTINGS"
    size_class: "large"
    // As wide as the three columns want, up to most of the screen; a fixed share of the height, so the drawer does
    // not resize between sections.
    readonly property real max_width_fraction: 0.9
    readonly property real height_fraction: 0.8
    // The section list, the pane and help column at their widest, their gaps and the body's 12px margins.
    readonly property real natural_width: nav.width + Style.px(12 + 24 + 860 + 48 + 520) + 24
    preferred_width: (root.screen ? Math.min(root.natural_width, root.screen.width * root.max_width_fraction) : root.natural_width) / Style.scale
    body_height: root.screen ? Math.min(root.screen.height * root.height_fraction - root.header_height - root.footer_height, root.content_cap + 24) : 600
    jumps_enabled: true
    // Only on the section list: panes hold sliders and fields with wheel behavior of their own.
    wheel_steps: !root.in_pane
    onWheel_stepped: (dir, horizontal) => {
        if (!horizontal) root.nav_index = root.clamp_index(root.nav_index, dir, 0, Sections.list.length);
    }
    search_enabled: true
    footer_hint: root.in_pane && root.pane ? root.pane.shown_hint : "/ find · j/k move · l enter · 1-9 pick · gg/G first/last · q close"

    // The lock's full-screen preview (LockPreview), for the lock section's p key.
    property var previewer: null

    property int nav_index: 0
    property bool in_pane: false
    property string loaded_id: ""
    readonly property var pane: pane_loader.item
    readonly property bool is_open: Popups.open_name === "settings"
    // Where SettingsPane puts its description block, and where a section docks its preview: the panel beside the rows.
    readonly property Item description_host: panel.help_host
    readonly property Item preview_host: panel.preview_host
    // Screen height left for the panel's body once the bar and the popup's own chrome are taken out; no cap before the screen is known.
    readonly property real free_height: {
        if (root.drawer && root.drawer_hole) return root.drawer_hole.h - root.header_height - root.footer_height;
        if (!root.screen) return Infinity;
        const bar = BarSettings.height_for(BarSettings.rule_for(root.screen)) + (Style.strip_floats ? Style.bar_strip_inset : 0);
        return root.screen.height - BarSettings.vertical_reserve(root.edge, bar, root.floating ? root.st.frame_float : 0) - root.header_height - root.footer_height - root.drop_room;
    }
    // The body adds a 12px margin on each side.
    readonly property real content_cap: Math.max(0, root.free_height - 24)

    search_rows: root.in_pane && root.pane ? root.pane.search_rows : Sections.list.map(s => s.label + " " + s.group + " " + s.keywords)
    search_cursor: root.in_pane && root.pane ? root.pane.search_cursor : root.nav_index
    onSearch_select: index => {
        if (root.in_pane && root.pane) root.pane.search_select(index);
        else root.nav_index = index;
    }
    onJump_first: root.jump(-1)
    onJump_last: root.jump(1)
    onNav_indexChanged: {
        if (!root.is_open) return;
        load_timer.restart();
        ThemeAudio.play("cursor");
        Qt.callLater(root.reveal_selected, nav_flick, nav_col);
    }

    Timer {
        id: load_timer
        interval: 120
        onTriggered: root.load_section()
    }
    onIs_openChanged: {
        load_timer.stop();
        if (!root.is_open) {
            root.in_pane = false;
            return;
        }
        if (!root.apply_request()) {
            root.load_section();
            root.leave_pane();
        }
        // nav_index may not change on open, so its own handler would not scroll the list to it.
        Qt.callLater(root.reveal_selected, nav_flick, nav_col);
    }

    function jump(delta) {
        if (root.in_pane && root.pane) root.pane.jump(delta);
        else root.nav_index = delta < 0 ? 0 : Sections.list.length - 1;
    }

    function load_section() {
        const section = Sections.list[root.nav_index];
        if (!section || root.loaded_id === section.id) return;
        root.loaded_id = section.id;
        pane_loader.setSource(Qt.resolvedUrl(section.source), { popup: root });
        pane_fade.restart();
    }

    function enter_pane() {
        load_timer.stop();
        root.load_section();
        if (!root.pane) return;
        root.in_pane = true;
        root.pane.forceActiveFocus();
        ThemeAudio.play("confirm");
    }

    function leave_pane() {
        if (root.in_pane) ThemeAudio.play("cancel");
        root.in_pane = false;
        nav.forceActiveFocus();
    }

    // Selects the section SettingsNav names and enters it; false when none was asked for.
    function apply_request() {
        const index = Sections.index_of(SettingsNav.requested);
        SettingsNav.requested = "";
        if (index < 0) return false;
        root.nav_index = index;
        root.load_section();
        root.enter_pane();
        return true;
    }

    // Drives the pane the way its keys would; a pane without the matching property or function ignores the command.
    function run_pane_command(name, value) {
        const pane = root.pane;
        if (!root.is_open || !root.in_pane || !pane) return;
        if (name === "back") {
            const editing = pane.editing === true || (typeof pane.edit_key === "string" && pane.edit_key !== "");
            if (pane.picking) pane.hide_picker();
            else if (editing && typeof pane.end_edit === "function") pane.end_edit();
            else root.leave_pane();
            return;
        }
        if (pane.picking || typeof pane.cursor !== "number") return;
        if (name === "cursor") pane.cursor = value;
        else if (name === "step" && typeof pane.step === "function") pane.step(pane.cursor, value);
        else if (name === "activate" && typeof pane.activate === "function") pane.activate(pane.cursor, 1);
    }

    // The first visible row flagged selected under `item`, or null.
    function selected_under(item) {
        for (const child of item.children) {
            if (!child.visible) continue;
            if (child.selected === true) return child;
            const found = root.selected_under(child);
            if (found) return found;
        }
        return null;
    }

    // Scrolls `flick` the least that shows the selected row under `scope`; a few px of lead keep a group heading with its first row.
    function reveal_selected(flick, scope) {
        const row = root.selected_under(scope);
        if (!row) return;
        const top = row.mapToItem(flick.contentItem, 0, 0).y;
        const lead = Style.px(24);
        let target = flick.contentY;
        if (top - lead < target) target = top - lead;
        else if (top + row.height > target + flick.height) target = top + row.height - flick.height;
        flick.contentY = Math.max(0, Math.min(target, flick.contentHeight - flick.height));
    }

    Connections {
        target: root.pane
        ignoreUnknownSignals: true
        function onCursorChanged() {
            Qt.callLater(root.reveal_selected, pane_flick, pane_loader);
        }
    }

    // The open picker moves its own cursor, which the pane's does not follow.
    Connections {
        target: root.pane ? root.pane.pick_list : null
        ignoreUnknownSignals: true
        function onCursorChanged() {
            Qt.callLater(root.reveal_selected, pane_flick, pane_loader);
        }
    }

    Connections {
        target: SettingsNav
        function onRequestedChanged() {
            if (root.is_open && SettingsNav.requested !== "") root.apply_request();
        }
        function onPane_command(name, value) {
            root.run_pane_command(name, value);
        }
    }

    FocusScope {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        height: root.body_height - 24
        focus: true

        // Runs after the section: Esc, h and Tab it did not use go back to the sidebar.
        Keys.onPressed: event => {
            if (!root.in_pane || (event.modifiers & Qt.ControlModifier)) return;
            const leave = (event.key === Qt.Key_H && !(event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab || (event.key === Qt.Key_Escape && root.search_query === "");
            if (!leave) return;
            root.leave_pane();
            event.accepted = true;
        }

        Flickable {
            id: nav_flick
            width: nav.width
            height: body.height
            // Only while scrolling: a selected row's glow reaches past the viewport edge, which fitting panels keep.
            clip: nav_flick.contentHeight > nav_flick.height
            contentWidth: width
            contentHeight: nav.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Item {
                id: nav
                readonly property real fit: {
                    let w = 0;
                    for (let i = 0; i < nav_repeater.count; i++) {
                        const item = nav_repeater.itemAt(i);
                        if (item) w = Math.max(w, item.need);
                    }
                    return w;
                }
                width: Math.max(Style.px(150), Math.ceil(nav.fit))
                implicitHeight: nav_col.implicitHeight
                focus: true

                Keys.onPressed: event => {
                    if (event.modifiers & Qt.ControlModifier) return;
                    const count = Sections.list.length;
                    if (event.key === Qt.Key_J) root.nav_index = root.wrap_index(root.nav_index, 1, 0, count);
                    else if (event.key === Qt.Key_K) root.nav_index = root.wrap_index(root.nav_index, -1, 0, count);
                    else if (event.key === Qt.Key_L || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) root.enter_pane();
                    else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.key - Qt.Key_1 < count) root.nav_index = event.key - Qt.Key_1;
                    else return;
                    event.accepted = true;
                }

                Column {
                    id: nav_col
                    width: parent.width
                    spacing: 4

                    Repeater {
                        id: nav_repeater
                        model: Sections.list

                        Column {
                            id: entry
                            required property int index
                            required property var modelData
                            readonly property bool first: entry.index === 0 || Sections.list[entry.index - 1].group !== entry.modelData.group
                            readonly property real need: 16 + nav_row.inset + nav_row.key_space + nav_layout.implicitWidth

                            width: nav_col.width
                            spacing: 4

                            MenuSection {
                                visible: entry.first
                                width: entry.width
                                topPadding: entry.index === 0 ? 0 : 6
                                label: entry.modelData.group
                            }

                            MenuRow {
                                id: nav_row
                                width: entry.width
                                height: Style.px(28)
                                base_radius: 6
                                selected: entry.index === root.nav_index
                                key: entry.index < 9 ? String(entry.index + 1) : ""

                                RowLayout {
                                    id: nav_layout
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8 + nav_row.inset
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8 + nav_row.key_space
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    Text {
                                        text: entry.modelData.glyph
                                        color: nav_row.fg(root.st.text_accent)
                                        font.family: root.st.font_family
                                        font.pixelSize: root.st.font_size
                                    }

                                    RowLabel {
                                        Layout.fillWidth: true
                                        label: entry.modelData.label
                                        color: nav_row.fg(root.st.text_fg)
                                        font.family: root.st.font_family
                                        font.pixelSize: root.st.font_size
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.nav_index = entry.index;
                                        root.enter_pane();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: nav_divider
            x: nav.width + Style.px(12)
            width: 1
            height: body.height
            color: Qt.alpha(root.st.text_muted, 0.4)
        }

        // Beside the section list there is room for the rows and the help column side by side, or (a portrait or
        // small screen) the help goes under the rows.
        readonly property real side_room: body.width - nav_divider.x - Style.px(24)
        readonly property bool help_below: body.side_room < Style.px(480 + 48 + 300)
        readonly property real help_width: body.help_below ? body.side_room : Math.max(Style.px(300), Math.min(Style.px(520), body.side_room * 0.32))
        readonly property real help_height: body.help_below ? Math.round(body.height * 0.3) : body.height
        readonly property real pane_width: body.help_below ? body.side_room : Math.min(Style.px(860), body.side_room - body.help_width - Style.px(48))
        readonly property real pane_height: body.help_below ? body.height - body.help_height - Style.px(24) : body.height

        Flickable {
            id: pane_flick
            x: nav_divider.x + Style.px(24)
            width: body.pane_width
            height: body.pane_height
            clip: pane_flick.contentHeight > pane_flick.height
            contentWidth: width
            contentHeight: pane_loader.height
            boundsBehavior: Flickable.StopAtBounds

            Loader {
                id: pane_loader
                width: pane_flick.width
                height: Math.max(pane_flick.height, pane_loader.implicitHeight)
                // The flickable is reused across sections: start the new one at the top, then at its selected row.
                onLoaded: {
                    pane_flick.contentY = 0;
                    Qt.callLater(root.reveal_selected, pane_flick, pane_loader);
                }
            }
        }

        Rectangle {
            x: body.help_below ? pane_flick.x : body.width - body.help_width - Style.px(12)
            y: body.help_below ? body.height - body.help_height - Style.px(12) : 0
            width: body.help_below ? body.help_width : 1
            height: body.help_below ? 1 : body.height
            color: Qt.alpha(root.st.text_muted, 0.4)
        }

        SettingsPanel {
            id: panel
            st: root.st
            stacked: body.help_below
            x: body.width - body.help_width
            y: body.height - body.help_height
            width: body.help_width
            height: body.help_height
        }

        NumberAnimation {
            id: pane_fade
            target: pane_loader
            property: "opacity"
            from: 0
            to: 1
            duration: 150
            easing.type: Easing.OutCubic
        }
    }
}
