pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.features.bar
import qs.ui.menu
import qs.features.popups.frames

// One per screen while the editor is open: draws the selection over that screen's live bar and swallows the pointer. Only
// the screen BarEditor.focus_screen names takes the keyboard and draws the mode, hints and boxes.
PanelWindow {
    id: root

    required property var modelData
    readonly property string screen_name: root.modelData.name
    readonly property bool keyboard_owner: BarEditor.keyboard_owner(root.screen_name)
    readonly property bool has_bar: BarEditor.monitors.some(m => m.name === root.screen_name)
    // A screen showing the layout being edited, which follows every change.
    readonly property bool peer: !root.keyboard_owner && BarEditor.sharing && BarEditor.sharing_screens().indexOf(root.screen_name) >= 0
    readonly property bool carrying: BarEditor.mode === "hidden" && BarEditor.picked !== ""
    readonly property bool shows_selection: BarEditor.mode === "normal" || root.carrying
    readonly property var bar_item: BarItems.item_of(root.screen_name, "bar")

    // The bar re-lays out a frame after an edit, so geometry is read again on a short tick.
    property int tick: 0
    // Where a module sits on this screen. The bar window is anchored to an edge, so its origin is not always the screen's; the Bar fills it.
    function rect_of(item) {
        const _ = root.tick;
        if (!item || !root.bar_item) return Qt.rect(0, 0, 0, 0);
        const p = item.mapToItem(root.bar_item, 0, 0);
        const ox = root.bar_item.position === "right" ? root.width - root.bar_item.width : 0;
        const oy = root.bar_item.position === "bottom" ? root.height - root.bar_item.height : 0;
        return Qt.rect(p.x + ox, p.y + oy, item.width, item.height);
    }
    // Where `entry` sits, or where it would: a module the bar hides while it has nothing to show is zero wide and has no
    // position of its own, so it takes the edge of the nearest shown module before it (else after it).
    function placed_rect(entry) {
        const own = root.rect_of(BarItems.item_of(root.screen_name, entry));
        if (own.width >= 1 && own.height >= 1) return { rect: own, found: true };
        const order = BarEditor.order;
        const at = order.indexOf(entry);
        for (let j = at - 1; j >= 0; j--) {
            const r = root.rect_of(BarItems.item_of(root.screen_name, order[j]));
            if (r.width >= 1 && r.height >= 1) return { rect: root.vertical ? Qt.rect(r.x, r.y + r.height, r.width, 0) : Qt.rect(r.x + r.width, r.y, 0, r.height), found: true };
        }
        for (let j = at + 1; at >= 0 && j < order.length; j++) {
            const r = root.rect_of(BarItems.item_of(root.screen_name, order[j]));
            if (r.width >= 1 && r.height >= 1) return { rect: root.vertical ? Qt.rect(r.x, r.y, r.width, 0) : Qt.rect(r.x, r.y, 0, r.height), found: true };
        }
        return { rect: own, found: false };
    }
    readonly property var placed: root.placed_rect(BarEditor.selected)
    readonly property rect sel: root.placed.rect
    readonly property bool vertical: root.bar_item !== null && root.bar_item.vertical
    readonly property rect bar_rect: root.rect_of(root.bar_item)
    // Hints go to the screen edge the bar is not on.
    readonly property bool hints_on_top: root.bar_item !== null && root.bar_item.position === "bottom"
    // With the screen frame on, the hints (and the monitor map) are HintDrawerWindow's drawer instead of HintBox and monitor_box.
    readonly property bool hints_in_drawer: ScreenFrames.layout_for(root.modelData) !== null
    // A module the bar hides while it has nothing to show is zero wide; it still gets a mark.
    readonly property real mark_width: Math.max(root.sel.width, 14)
    readonly property real mark_x: root.sel.x - (root.mark_width - root.sel.width) / 2
    readonly property real mark_height: Math.max(root.sel.height, 14)
    readonly property real mark_y: root.sel.y - (root.mark_height - root.sel.height) / 2

    function spec_of(event) {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        if (event.key === Qt.Key_Escape) return "Esc";
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) return "Enter";
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) return "Tab";
        if (event.key === Qt.Key_Backspace) return "Backspace";
        if (ctrl) return event.key === Qt.Key_R ? "Ctrl+r" : "";
        return event.text.length === 1 && event.text >= " " ? event.text : "";
    }

    screen: root.modelData
    visible: BarEditor.active
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-bareditor"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive on the owner only: with OnDemand the keyboard stays where it was when monitor select hands the editor to another
    // screen, until the pointer enters that screen. Unlike RegionSelector this loses nothing, since every screen's pointer is swallowed anyway.
    // The claim waits a beat after the old owner lets go: when both commits land together, Hyprland can leave the keyboard
    // with nobody, and the editor then gets no keys until it is reopened.
    property bool claims_keyboard: false
    // Works around that Hyprland race; the value was found by test. Known limit: keys pressed during the gap reach no editor window.
    readonly property int claim_delay_ms: 60
    WlrLayershell.keyboardFocus: root.claims_keyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    Timer {
        id: claim_delay
        interval: root.claim_delay_ms
        onTriggered: root.claims_keyboard = root.keyboard_owner
    }

    // Hyprland skips every bind while the editor has the keyboard, so none can act on the bar being edited.
    ShortcutInhibitor {
        window: root
        enabled: root.keyboard_owner
    }

    Timer {
        interval: 80
        repeat: true
        running: root.visible
        onTriggered: root.tick++
    }

    onKeyboard_ownerChanged: {
        if (root.keyboard_owner) {
            claim_delay.restart();
            Qt.callLater(() => keys_item.forceActiveFocus());
        } else {
            claim_delay.stop();
            root.claims_keyboard = false;
        }
    }

    // Nothing under the editor sees the pointer.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    Item {
        id: keys_item
        focus: true
        Keys.onPressed: event => {
            const spec = root.spec_of(event);
            event.accepted = true;
            if (spec !== "") BarEditor.press(spec);
        }
        Component.onCompleted: if (root.keyboard_owner) keys_item.forceActiveFocus()
    }

    // The bar being edited, outlined so the active monitor stands out even when others share its layout.
    Rectangle {
        visible: root.keyboard_owner && BarEditor.mode !== "monitor" && BarEditor.mode !== "visual" && root.bar_item !== null
        x: root.bar_rect.x
        y: root.bar_rect.y
        width: root.bar_rect.width
        height: root.bar_rect.height
        color: Qt.alpha(Theme.theme_primary, 0.08)
        border.width: 1
        border.color: Theme.theme_primary
    }

    // The selected module: a line along the bar's inner edge and a caret pointing at it. A screen sharing the layout shows it fainter.
    Item {
        visible: root.shows_selection && root.placed.found && (root.keyboard_owner || root.peer)
        opacity: root.keyboard_owner ? 1 : 0.45
        Rectangle {
            x: root.vertical ? root.bar_rect.x + (root.bar_item && root.bar_item.position === "right" ? 0 : root.bar_rect.width - 3) : root.mark_x
            y: root.vertical ? root.mark_y : root.bar_rect.y + (root.bar_item && root.bar_item.position === "bottom" ? 0 : root.bar_rect.height - 3)
            width: root.vertical ? 3 : root.mark_width
            height: root.vertical ? root.mark_height : 3
            color: Theme.theme_secondary
        }
        Text {
            id: caret
            readonly property bool flipped: root.bar_item !== null && (root.bar_item.position === "bottom" || root.bar_item.position === "right")
            text: root.vertical ? (flipped ? "◀" : "▶") : (flipped ? "▼" : "▲")
            color: Theme.theme_secondary
            font.pixelSize: Style.fs(-2)
            x: root.vertical ? (flipped ? root.bar_rect.x - width - 2 : root.bar_rect.x + root.bar_rect.width + 2) : root.sel.x + root.sel.width / 2 - width / 2
            y: root.vertical ? root.sel.y + root.sel.height / 2 - height / 2 : (flipped ? root.bar_rect.y - height - 1 : root.bar_rect.y + root.bar_rect.height + 1)
        }
        // The module's name past the caret, away from the bar, on a plate so it reads over any wallpaper.
        Rectangle {
            width: name_text.implicitWidth + 12
            height: name_text.implicitHeight + 4
            radius: Math.min(Style.frame_radius, 4)
            color: Style.frame_color
            border.width: 1
            border.color: Theme.theme_secondary
            x: root.vertical ? (caret.flipped ? caret.x - width - 4 : caret.x + caret.width + 4) : Math.max(4, Math.min(root.width - width - 4, caret.x + caret.width / 2 - width / 2))
            y: root.vertical ? caret.y + caret.height / 2 - height / 2 : (caret.flipped ? caret.y - height - 2 : caret.y + caret.height + 2)
            Text {
                id: name_text
                anchors.centerIn: parent
                text: BarEditor.selected
                color: Theme.theme_secondary
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
            }
        }
    }

    // Modules with a compact override of their own: a dot at the module's corner, filled when forced on, a ring when forced off.
    // `compact_marks_for` reads the bars.json rule matching this screen, not the picked monitor's: rules can name different per-module overrides.
    Repeater {
        model: (root.keyboard_owner || root.peer) && (BarEditor.mode === "normal" || BarEditor.mode === "hidden") ? BarEditor.compact_marks_for(root.screen_name) : []
        Rectangle {
            id: compact_mark
            required property var modelData
            readonly property var placed: root.placed_rect(compact_mark.modelData.entry)
            readonly property rect at: compact_mark.placed.rect
            // A module drawn with nothing (compact system) is zero wide at its slot, so the mark gets a span of its own there.
            readonly property real span_w: Math.max(compact_mark.at.width, 14)
            readonly property real span_h: Math.max(compact_mark.at.height, 14)
            readonly property bool forced_on: compact_mark.modelData.on
            visible: compact_mark.placed.found
            opacity: root.keyboard_owner ? 1 : 0.45
            width: 7
            height: 7
            radius: 3.5
            x: compact_mark.at.x - (compact_mark.span_w - compact_mark.at.width) / 2 + compact_mark.span_w - width
            y: compact_mark.at.y - (compact_mark.span_h - compact_mark.at.height) / 2
            color: compact_mark.forced_on ? Theme.theme_secondary : "transparent"
            border.width: 1.5
            border.color: Theme.theme_secondary
        }
    }

    // VISUAL: the whole bar, framed; a screen sharing the edge shows it fainter.
    Rectangle {
        visible: BarEditor.mode === "visual" && root.bar_item !== null && (root.keyboard_owner || root.peer)
        opacity: root.keyboard_owner ? 1 : 0.45
        x: root.bar_rect.x
        y: root.bar_rect.y
        width: root.bar_rect.width
        height: root.bar_rect.height
        color: Qt.alpha(Style.accent_color, 0.12)
        border.width: 2
        border.color: Style.accent_color
    }

    // Monitor select: every screen with a bar gets an inset frame, the picked one in the accent.
    Rectangle {
        visible: BarEditor.mode === "monitor" && root.has_bar
        anchors.fill: parent
        anchors.margins: 4
        color: "transparent"
        border.width: root.keyboard_owner ? 3 : 1
        border.color: root.keyboard_owner ? Style.accent_color : Style.frame_border_color
    }

    // HIDDEN: the hidden modules and the argument variants not on the bar, away from the hint bar.
    Rectangle {
        visible: root.keyboard_owner && BarEditor.mode === "hidden" && BarEditor.picked === ""
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.hints_on_top ? hint_box.y + hint_box.height + 10 : hint_box.y - height - 10
        width: Math.min(parent.width - 64, tray_row.implicitWidth + 24)
        height: tray_row.implicitHeight + 16
        radius: Style.frame_radius
        color: Style.frame_color
        border.width: Style.frame_border_width
        border.color: Style.frame_border_color
        clip: true
        Row {
            id: tray_row
            // Centered when it fits; wider than the tray it slides so the selected chip stays in view.
            readonly property real room: parent.width - 24
            property real selected_center: 0
            x: tray_row.implicitWidth <= tray_row.room ? 12 + (tray_row.room - tray_row.implicitWidth) / 2 : 12 - Math.max(0, Math.min(tray_row.implicitWidth - tray_row.room, tray_row.selected_center - tray_row.room / 2))
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text {
                visible: BarEditor.hidden_list.length === 0
                text: "nothing to add"
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }
            Repeater {
                model: BarEditor.hidden_list
                Rectangle {
                    id: chip
                    required property string modelData
                    readonly property bool current: modelData === BarEditor.hidden_selected
                    width: chip_text.implicitWidth + 16
                    height: chip_text.implicitHeight + 8
                    radius: Style.frame_radius
                    color: chip.current ? Qt.alpha(Style.accent_color, 0.3) : "transparent"
                    border.width: chip.current ? 2 : 1
                    border.color: chip.current ? Style.accent_color : Style.frame_border_color
                    Binding {
                        target: tray_row
                        property: "selected_center"
                        value: chip.x + chip.width / 2
                        when: chip.current
                    }
                    Text {
                        id: chip_text
                        anchors.centerIn: parent
                        text: chip.modelData
                        color: Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-1)
                    }
                }
            }
        }
    }

    // The key hints, on the screen edge the bar is not on.
    HintBox {
        id: hint_box
        visible: root.keyboard_owner && BarEditor.mode !== "monitor" && !root.hints_in_drawer
        on_top: root.hints_on_top
        carrying: root.carrying
        vertical: root.vertical
    }

    // Monitor select: the screens as they sit, the picked one lit.
    Item {
        id: monitor_box
        visible: root.keyboard_owner && BarEditor.mode === "monitor" && !root.hints_in_drawer
        anchors.centerIn: parent
        width: 560
        height: monitor_map.map_height + 130
        Rectangle {
            anchors.fill: parent
            radius: Style.frame_radius
            color: Style.frame_color
            border.width: Style.frame_border_width
            border.color: Style.frame_border_color
        }
        Text {
            x: 20
            y: 12
            text: "-- MONITOR --"
            color: Style.text_primary
            font.family: Style.title_font_family
            font.pixelSize: Style.fs(-1)
            font.bold: true
        }
        MonitorMap {
            id: monitor_map
            x: 20
            y: 44
        }
        HintContent {
            x: 10
            y: monitor_map.map_height + 62
            width: 540
            box_titled: true
        }
    }

    // Help box.
    Rectangle {
        id: help_box
        visible: root.keyboard_owner && BarEditor.help_open
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, Style.px(520))
        height: Math.min(parent.height - 160, Style.px(440))
        radius: Style.frame_radius
        color: Style.frame_color
        border.width: Style.frame_border_width
        border.color: Style.frame_border_color
        Rectangle {
            width: parent.width
            height: Style.accent_height
            color: Style.accent_color
            topLeftRadius: help_box.radius
            topRightRadius: help_box.radius
        }
        Rectangle {
            y: Style.accent_height
            width: parent.width
            height: help_title.height + 20
            color: Style.title_bg
        }
        Text {
            id: help_title
            x: 16
            y: 10 + Style.accent_height
            text: Style.title_text("Bar editor keys", Style)
            color: Style.title_fg
            font.family: Style.title_font_family
            font.pixelSize: Style.fs(-2)
        }
        KeyHelp {
            anchors.fill: parent
            anchors.topMargin: help_title.y + help_title.height + 8
            anchors.margins: 12
            popup_keys: false
            text: "h/l select module · H/L move module · c module compact (inherit, on, off) · o own layout · x hide · u undo · Ctrl+R redo · Tab hidden modules · Shift+V whole bar (then hjkl moves it to an edge, c toggles the bar's compact, x forgets the saved position, u undoes) · Esc monitor select · q close"
        }
    }
}
