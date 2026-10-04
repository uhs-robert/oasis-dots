// home/quickshell/.config/quickshell/components/RegionSelector.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../services"
import "picker"
import "picker/cursors" as Cursors
import "picker/targets" as Targets

// One per screen while Screenshot.selecting: drag a region, then pick an action from the toolbar.
PanelWindow {
    id: root

    required property var modelData
    readonly property string screen_name: root.modelData.name
    readonly property bool keyboard_owner: Screenshot.focus_screen === root.screen_name
    readonly property bool mine: Screenshot.sel_screen === root.screen_name && Screenshot.has_selection
    readonly property rect sel: root.mine ? Screenshot.sel_rect : Qt.rect(0, 0, 0, 0)
    readonly property bool toolbar_shown: root.mine && Screenshot.phase === "toolbar"
    // Hidden while grim reads the screen, and until the still frame is in so the chrome never lands in it.
    readonly property bool chrome_shown: Screenshot.phase !== "capture" && (root.pixel_mode ? root.frame_ready || root.grab_failed : frozen_view.hasContent || !Screenshot.frozen && root.waited)
    property bool waited: false
    // Buffer pixels per logical pixel, so the loupe magnifies real screen pixels.
    readonly property real buffer_scale: frozen_view.sourceSize.width > 0 ? frozen_view.sourceSize.width / root.width : root.modelData.devicePixelRatio
    readonly property color dim_color: Qt.alpha(Theme.bg_shadow, 0.6)
    readonly property bool pixel_mode: Screenshot.mode === "pixel"
    readonly property bool target_mode: Screenshot.mode === "window" || Screenshot.mode === "screen"
    // A region for the share overview's pending request: Esc goes back there instead of cancelling.
    readonly property bool sharing: Screenshot.preset === "share"
    readonly property bool skinned_targets: targets_loader.status === Loader.Ready
    readonly property bool skinned_cursor: cursor_loader.status === Loader.Ready
    property bool help_open: false
    readonly property string delay_label: Screenshot.delay_s > 0 ? "Delay " + Screenshot.delay_s + "s" : "No delay"
    readonly property string tier_keys: "hjkl move 10px · H/J/K/L move 100px · C-hjkl move 1px · C-H/J/K/L move 300px"
    readonly property string help_text: Screenshot.phase === "toolbar" ? "h/l move · Tab/S-Tab next/prev · c copy · s save · a annotate · o ocr · t scroll text · i scroll image · r record" + (Screenshot.frozen ? "" : " · d delay off/3s/5s/10s") + " · Enter run · Esc/Backspace adjust selection · q cancel" : root.pixel_mode ? root.tier_keys + " · Enter pick · click pick · m loupe · i/o or +/- zoom · [/] loupe size · q/Esc cancel" : root.target_mode ? "hjkl nearest " + Screenshot.mode + " · Tab/S-Tab cycle · d delay off/3s/5s/10s · Enter pick · click pick · m loupe · i/o or +/- zoom · [/] loupe size · q/Esc cancel" : root.tier_keys + " · space anchor, then confirm · v set or drop anchor · O swap ends · drag select · Enter confirm, whole screen without a selection · m loupe · i/o or +/- zoom · [/] loupe size · Esc drop anchor, then " + (root.sharing ? "back to the share overview · q cancel the share" : "cancel · q cancel")

    function cursor_key() {
        return Screenshot.target_index + "|" + Screenshot.tool_index;
    }
    function play_if_moved(before) {
        if (root.cursor_key() !== before) ThemeAudio.play("cursor");
    }

    function set_help(open) {
        root.help_open = open;
        Qt.callLater(() => open ? key_help.forceActiveFocus() : keys_item.forceActiveFocus());
    }
    // Pixel mode freezes with grim's own capture of this output (real pixels on every scale), taken before
    // anything is drawn; it is the background, the loupe's source and what the swatch samples.
    property string pixel_file: ""
    property int grab_tries: 0
    property bool grab_failed: false
    Component.onCompleted: if (root.pixel_mode) {
        root.pixel_file = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-pixel-" + root.screen_name + "-" + Date.now() + ".png";
        root.start_frame_grab();
    }

    // The command is set before starting: bound running/command could start grim with the old, empty path.
    function start_frame_grab() {
        root.grab_tries += 1;
        frame_grab.command = ["grim", "-o", root.screen_name, root.pixel_file];
        frame_grab.running = true;
    }

    // Only the cursor's screen is needed to pick; another screen that can't be grabbed just stays unfrozen.
    function frame_grab_failed(reason) {
        root.grab_failed = true;
        console.warn("RegionSelector: grim -o " + root.screen_name + " failed: " + reason);
        if (Screenshot.cursor_screen === root.screen_name) Screenshot.fail("grim could not capture " + root.screen_name + (reason !== "" ? ": " + reason : ""));
    }
    property string pixel_image: ""
    readonly property bool frame_ready: frame_image.status === Image.Ready && frame_image.sourceSize.width > 0
    readonly property real pixel_scale: root.frame_ready ? frame_image.sourceSize.width / root.width : root.buffer_scale
    readonly property real sample_scale: root.pixel_mode ? root.pixel_scale : root.buffer_scale

    Process {
        id: frame_grab
        stderr: StdioCollector {
            id: frame_grab_err
        }
        onExited: code => {
            if (code === 0) root.pixel_image = "file://" + root.pixel_file;
            else if (root.grab_tries < 3) frame_retry.restart();
            else root.frame_grab_failed(frame_grab_err.text.trim() || "exit " + code);
        }
    }

    Timer {
        id: frame_retry
        interval: 150
        onTriggered: root.start_frame_grab()
    }

    Component.onDestruction: if (root.pixel_file !== "") Quickshell.execDetached(["rm", "-f", "--", root.pixel_file])

    screen: root.modelData
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "quickshell-region"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive would make Hyprland send every screen's pointer input to this one surface.
    WlrLayershell.keyboardFocus: root.keyboard_owner ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Hyprland skips every bind while this holds focus, so SUPER+hjkl cannot move focus off a share pick.
    ShortcutInhibitor {
        window: root
        enabled: root.sharing && root.keyboard_owner
    }

    property point press_point: Qt.point(0, 0)
    property point last_mouse: Qt.point(-1, -1)

    function run_tool(index) {
        const action = Screenshot.actions[index];
        if (!action) return;
        ThemeAudio.play("confirm");
        Screenshot.act(action.id);
    }

    // One still frame per screen: the frozen background, and the loupe's source in both modes.
    ScreencopyView {
        id: frozen_view
        anchors.fill: parent
        visible: Screenshot.frozen && !root.pixel_mode
        captureSource: root.modelData
        live: false
        paintCursor: false
        onStopped: if (Screenshot.frozen && !root.pixel_mode && !frozen_view.hasContent) Screenshot.fail("Frozen capture failed")
    }

    Image {
        id: frame_image
        anchors.fill: parent
        visible: root.frame_ready
        source: root.pixel_image
        cache: false
        smooth: false
    }

    Timer {
        running: true
        interval: 300
        onTriggered: root.waited = true
    }

    Timer {
        running: Screenshot.frozen && !root.grab_failed && !(root.pixel_mode ? root.frame_ready : frozen_view.hasContent)
        interval: root.pixel_mode ? 4000 : 1500
        onTriggered: root.pixel_mode ? root.frame_grab_failed("timed out") : Screenshot.fail("Frozen capture timed out")
    }

    Item {
        id: chrome
        anchors.fill: parent
        visible: root.chrome_shown

        Rectangle {
            visible: !root.mine && !root.pixel_mode
            anchors.fill: parent
            color: root.dim_color
        }

        Rectangle {
            visible: root.mine
            width: parent.width
            height: root.sel.y
            color: root.dim_color
        }

        Rectangle {
            visible: root.mine
            y: root.sel.y + root.sel.height
            width: parent.width
            height: parent.height - y
            color: root.dim_color
        }

        Rectangle {
            visible: root.mine
            y: root.sel.y
            width: root.sel.x
            height: root.sel.height
            color: root.dim_color
        }

        Rectangle {
            visible: root.mine
            x: root.sel.x + root.sel.width
            y: root.sel.y
            width: parent.width - x
            height: root.sel.height
            color: root.dim_color
        }

        Repeater {
            model: root.target_mode ? Screenshot.targets : []

            Rectangle {
                required property var modelData
                required property int index
                visible: !root.skinned_targets && modelData.screen === root.screen_name && index !== Screenshot.target_index && Screenshot.phase === "select"
                x: modelData.rect.x
                y: modelData.rect.y
                width: modelData.rect.width
                height: modelData.rect.height
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Style.accent_color, 0.5)
            }
        }

        Item {
            id: frame
            readonly property int edge: Math.max(1, Style.frame_border_width)
            visible: root.mine && !root.skinned_targets
            x: root.sel.x - frame.edge
            y: root.sel.y - frame.edge
            width: root.sel.width + frame.edge * 2
            height: root.sel.height + frame.edge * 2

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: frame.edge
                border.color: Style.accent_color
            }

            CornerBrackets {
                anchors.fill: parent
                color: Style.caret_color
                inset: -2
                arm: Math.min(18, Math.max(6, Math.min(root.sel.width, root.sel.height) / 3))
                thickness: 3
                all_corners: true
            }
        }

        Loader {
            id: targets_loader
            readonly property string skin: Style.picker_skin
            anchors.fill: parent
            visible: !root.pixel_mode
            active: targets_loader.skin !== ""
            onSkinChanged: targets_loader.load()
            Component.onCompleted: targets_loader.load()

            function load() {
                if (targets_loader.skin === "")
                    return;
                targets_loader.setSource(Qt.resolvedUrl("picker/targets/" + targets_loader.skin.charAt(0).toUpperCase() + targets_loader.skin.slice(1) + ".qml"), {
                    screen_name: Qt.binding(() => root.screen_name),
                    origin: Qt.binding(() => Qt.point(root.modelData.x, root.modelData.y)),
                    sel: Qt.binding(() => root.sel),
                    mine: Qt.binding(() => root.mine),
                    target_mode: Qt.binding(() => root.target_mode)
                });
            }
        }

        Rectangle {
            id: readout
            visible: root.mine && !root.skinned_targets
            readonly property bool above: root.sel.y >= height + 8
            x: Math.max(0, Math.min(parent.width - width, root.sel.x))
            y: readout.above ? root.sel.y - height - 6 : root.sel.y + 6
            width: readout_text.implicitWidth + 16
            height: readout_text.implicitHeight + 6
            radius: Style.radius(3)
            color: Style.title_bg
            border.width: Style.frame_border_width > 0 ? 1 : 0
            border.color: Style.frame_border_color

            Text {
                id: readout_text
                anchors.centerIn: parent
                text: Math.round(root.sel.width) + " x " + Math.round(root.sel.height)
                color: Style.title_fg
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-3)
            }
        }

        Rectangle {
            id: toolbar
            visible: root.toolbar_shown
            readonly property real gap: 10
            readonly property bool below: root.sel.y + root.sel.height + gap + height <= parent.height
            readonly property bool over: !toolbar.below && root.sel.y >= height + gap + readout.height + 12
            x: Math.max(8, Math.min(parent.width - width - 8, root.sel.x + (root.sel.width - width) / 2))
            y: toolbar.below ? root.sel.y + root.sel.height + gap : toolbar.over ? root.sel.y - height - gap - (readout.above ? readout.height + 6 : 0) : root.sel.y + root.sel.height - height - gap
            width: tools_row.implicitWidth + 16
            height: tools_row.implicitHeight + 16 + Style.accent_height
            radius: Style.frame_radius
            color: Style.frame_color
            border.width: Style.frame_border_width
            border.color: Style.frame_border_color

            MouseArea {
                anchors.fill: parent
            }

            Rectangle {
                width: parent.width
                height: Style.accent_height
                color: Style.accent_color
                topLeftRadius: toolbar.radius
                topRightRadius: toolbar.radius
            }

            RowLayout {
                id: tools_row
                x: 8
                y: 8 + Style.accent_height
                spacing: 4

                Repeater {
                    model: Screenshot.actions

                    MenuRow {
                        id: tool
                        required property int index
                        required property var modelData

                        Layout.preferredWidth: tool_label.implicitWidth + 16 + tool.inset + tool.key_space
                        Layout.preferredHeight: Style.px(28)
                        base_radius: 6
                        selected: tool.index === Screenshot.tool_index
                        key: tool.modelData.key

                        Text {
                            id: tool_label
                            anchors.left: parent.left
                            anchors.leftMargin: 8 + tool.inset
                            anchors.verticalCenter: parent.verticalCenter
                            text: tool.modelData.label
                            color: tool.fg(Style.text_fg)
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: Screenshot.tool_index = tool.index
                            onClicked: root.run_tool(tool.index)
                        }
                    }
                }

                MenuRow {
                    id: delay_tool
                    visible: !Screenshot.frozen
                    Layout.preferredWidth: delay_label.implicitWidth + 16 + delay_tool.inset + delay_tool.key_space
                    Layout.preferredHeight: Style.px(28)
                    base_radius: 6
                    key: "d"

                    Text {
                        id: delay_label
                        anchors.left: parent.left
                        anchors.leftMargin: 8 + delay_tool.inset
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.delay_label
                        color: Screenshot.delay_s > 0 ? Theme.warning : Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Screenshot.cycle_delay()
                    }
                }
            }
        }

        Item {
            id: key_cursor
            readonly property point at: Screenshot.cursor_point
            readonly property int arm: 12
            readonly property bool hide_arms: root.skinned_cursor && !root.target_mode
            visible: Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name && (Screenshot.keys_moved || Screenshot.anchored)

            Item {
                visible: !key_cursor.hide_arms

                Repeater {
                    model: [[-key_cursor.arm - 3, 0, key_cursor.arm, 1], [4, 0, key_cursor.arm, 1], [0, -key_cursor.arm - 3, 1, key_cursor.arm], [0, 4, 1, key_cursor.arm]]

                    Rectangle {
                        required property var modelData
                        x: key_cursor.at.x + modelData[0]
                        y: key_cursor.at.y + modelData[1]
                        width: modelData[2]
                        height: modelData[3]
                        color: Style.caret_color
                        border.width: 0
                    }
                }
            }

            Rectangle {
                visible: Screenshot.anchored
                x: Screenshot.anchor_point.x - 3
                y: Screenshot.anchor_point.y - 3
                width: 7
                height: 7
                color: "transparent"
                border.width: 1
                border.color: Style.accent_color
            }
        }

        Loader {
            id: cursor_loader
            readonly property string skin: Style.picker_skin
            anchors.fill: parent
            active: cursor_loader.skin !== ""
            onSkinChanged: cursor_loader.load()
            Component.onCompleted: cursor_loader.load()

            function load() {
                if (cursor_loader.skin === "")
                    return;
                const props = {
                    screen_name: Qt.binding(() => root.screen_name),
                    origin: Qt.binding(() => Qt.point(root.modelData.x, root.modelData.y)),
                    target_mode: Qt.binding(() => root.target_mode)
                };
                if (cursor_loader.skin === "scope") {
                    props.box_w = Qt.binding(() => Screenshot.lens_on ? Math.ceil(picker_loupe.sample_half) * 2 + 5 : 58);
                    props.box_h = Qt.binding(() => Screenshot.lens_on ? Math.ceil(picker_loupe.sample_half) * 2 + 5 : 38);
                }
                cursor_loader.setSource(Qt.resolvedUrl("picker/cursors/" + cursor_loader.skin.charAt(0).toUpperCase() + cursor_loader.skin.slice(1) + ".qml"), props);
            }
        }

        Loupe {
            id: picker_loupe
            visible: Screenshot.lens_on && Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name && (root.pixel_mode ? root.frame_ready : frozen_view.hasContent)
            at: Screenshot.cursor_point
            source: root.pixel_mode ? frame_image : frozen_view
            sample_scale: root.sample_scale
            pixel_mode: root.pixel_mode
            screen_name: root.screen_name
            screen_x: root.modelData.x
            screen_y: root.modelData.y
            area_width: root.width
            area_height: root.height
            has_sel: root.mine
            sel: root.sel
            pixel_image: root.pixel_image
            frame_size: frame_image.sourceSize
            scan_complete: cursor_loader.item?.complete ?? false
            scan_step: cursor_loader.item?.scan_step ?? -1
            scan_steps: cursor_loader.item?.scan_steps ?? 6
        }

        Rectangle {
            id: help_box
            visible: root.keyboard_owner && root.help_open
            z: 3
            anchors.centerIn: parent
            width: Math.min(parent.width - 64, Style.px(520))
            height: Math.min(parent.height - 160, Style.px(440))
            radius: Style.frame_radius
            color: Style.frame_color
            border.width: Style.frame_border_width
            border.color: Style.frame_border_color

            MouseArea {
                anchors.fill: parent
            }

            Rectangle {
                width: parent.width
                height: Style.accent_height
                color: Style.accent_color
                topLeftRadius: help_box.radius
                topRightRadius: help_box.radius
            }

            Text {
                id: help_title
                x: 16
                y: 10 + Style.accent_height
                text: Style.title_text("Screenshot keys", Style)
                color: Style.title_fg
                font.family: Style.title_font_family
                font.pixelSize: Style.fs(-2)
            }

            KeyHelp {
                id: key_help
                anchors.fill: parent
                anchors.topMargin: help_title.y + help_title.height + 8
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.bottomMargin: 12
                popup_keys: false
                text: root.help_text
                onBack: root.set_help(false)
            }
        }

        Rectangle {
            id: hint_box
            visible: root.keyboard_owner
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            width: Math.min(parent.width - 32, hint.implicitWidth + 24)
            height: hint.implicitHeight + 12
            radius: Style.frame_radius
            color: Style.frame_color
            border.width: Style.frame_border_width
            border.color: Style.frame_border_color

            MenuFooter {
                id: hint
                anchors.centerIn: parent
                width: Math.min(implicitWidth, root.width - 56)
                wrap: false
                text: (root.sharing ? "Share region · " : "") + (root.target_mode && Screenshot.phase === "select" ? "hjkl/Tab " + Screenshot.mode + " · d " + root.delay_label.toLowerCase() + " · Enter pick · Esc cancel" : root.pixel_mode ? "hjkl move · Enter pick · m loupe · i/o zoom · Esc cancel" : Screenshot.phase === "toolbar" ? "h/l move · Enter run · c copy · s save · a annotate · o ocr · t scroll text · i scroll image · r record" + (Screenshot.frozen ? "" : " · d delay") + " · Esc/Backspace adjust · q cancel" : Screenshot.anchored ? "hjkl extend · O swap ends · v/Esc drop anchor · Space/Enter " + (Screenshot.preset !== "" ? Screenshot.preset : "confirm") : "drag/hjkl cursor · v/space anchor · Enter full screen · m loupe · i/o zoom · " + (root.sharing ? "Esc back · q cancel" : "Esc cancel")) + " · ? help"
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: Screenshot.phase === "select" || Screenshot.phase === "toolbar"
        cursorShape: root.skinned_cursor && Screenshot.phase === "select" && !root.target_mode && root.chrome_shown ? Qt.BlankCursor : Qt.CrossCursor
        hoverEnabled: true
        onWheel: wheel => Screenshot.step_zoom(wheel.angleDelta.y > 0 ? 1 : wheel.angleDelta.y < 0 ? -1 : 0)
        onPressed: mouse => {
            if (root.target_mode) {
                const i = Screenshot.target_at(root.screen_name, mouse.x, mouse.y);
                if (i < 0) return;
                Screenshot.phase = "select";
                Screenshot.highlight(i);
                ThemeAudio.play("confirm");
                Screenshot.confirm();
                return;
            }
            if (root.pixel_mode) {
                if (!root.frame_ready) return;
                Screenshot.set_cursor(root.screen_name, mouse.x, mouse.y, false);
                ThemeAudio.play("confirm");
                Screenshot.pick_pixel();
                return;
            }
            Screenshot.anchored = false;
            root.press_point = Qt.point(mouse.x, mouse.y);
            Screenshot.phase = "select";
            Screenshot.set_selection(root.screen_name, mouse.x, mouse.y, 0, 0);
        }
        onPositionChanged: mouse => {
            // Qt re-sends hover at a resting pointer when the scene changes; only real motion takes the cursor back.
            // The first report is only a baseline: it may be one of those re-sends before the pointer ever moved.
            const first = root.last_mouse.x < 0 && !pressed;
            if (mouse.x === root.last_mouse.x && mouse.y === root.last_mouse.y && !pressed) return;
            root.last_mouse = Qt.point(mouse.x, mouse.y);
            if (first) return;
            Screenshot.set_cursor(root.screen_name, mouse.x, mouse.y, false);
            if (root.target_mode && Screenshot.phase === "select") {
                const i = Screenshot.target_at(root.screen_name, mouse.x, mouse.y);
                if (i >= 0 && i !== Screenshot.target_index) Screenshot.highlight(i);
                return;
            }
            if (!pressed || root.pixel_mode) return;
            const x = Math.max(0, Math.min(root.width, mouse.x));
            const y = Math.max(0, Math.min(root.height, mouse.y));
            const p = root.press_point;
            Screenshot.set_selection(root.screen_name, Math.min(p.x, x), Math.min(p.y, y), Math.abs(x - p.x), Math.abs(y - p.y));
        }
        onReleased: {
            if (root.pixel_mode || root.target_mode) return;
            if (Screenshot.has_selection) {
                ThemeAudio.play("confirm");
                Screenshot.confirm();
            } else {
                Screenshot.sel_screen = "";
            }
        }
    }

    Item {
        id: keys_item
        anchors.fill: parent
        focus: root.keyboard_owner
        Component.onCompleted: if (root.keyboard_owner) keys_item.forceActiveFocus()

        // Direction keys held down, so two of them move the cursor diagonally like the Cursor submap.
        property var held: ({})

        readonly property string phase: Screenshot.phase
        onPhaseChanged: keys_item.held = {}

        Keys.onReleased: event => {
            if (!event.isAutoRepeat) delete keys_item.held[event.key];
        }

        Keys.onPressed: event => {
            const before = root.cursor_key();
            const shift = event.modifiers & Qt.ShiftModifier;
            const ctrl = event.modifiers & Qt.ControlModifier;
            // The Cursor submap's tiers: 10px, Shift 100, Ctrl 1, Ctrl+Shift 300.
            const step = ctrl && shift ? 300 : shift ? 100 : ctrl ? 1 : 10;
            const toolbar = Screenshot.phase === "toolbar";
            const typed = toolbar ? Screenshot.actions.findIndex(a => a.key === event.text) : -1;
            const dir = { [Qt.Key_H]: [-1, 0], [Qt.Key_Left]: [-1, 0], [Qt.Key_L]: [1, 0], [Qt.Key_Right]: [1, 0], [Qt.Key_K]: [0, -1], [Qt.Key_Up]: [0, -1], [Qt.Key_J]: [0, 1], [Qt.Key_Down]: [0, 1] }[event.key];
            if (Screenshot.phase === "capture") {
                return;
            } else if (event.key === Qt.Key_Question || event.text === "?") {
                root.set_help(true);
            } else if (event.key === Qt.Key_Escape) {
                ThemeAudio.play("cancel");
                if (toolbar) Screenshot.reselect();
                else if (Screenshot.anchored) Screenshot.clear_anchor();
                else if (root.sharing) Screenshot.share_back();
                else Screenshot.cancel();
            } else if (event.key === Qt.Key_Q) {
                ThemeAudio.play("cancel");
                Screenshot.cancel();
            } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.text === "+" || event.text === "=") {
                Screenshot.step_zoom(1);
            } else if (event.key === Qt.Key_Minus || event.text === "-") {
                Screenshot.step_zoom(-1);
            } else if (event.key === Qt.Key_BracketLeft || event.text === "[") {
                Screenshot.step_lens(-1);
            } else if (event.key === Qt.Key_BracketRight || event.text === "]") {
                Screenshot.step_lens(1);
            } else if (!toolbar && !shift && (event.key === Qt.Key_I || event.key === Qt.Key_O)) {
                Screenshot.step_zoom(event.key === Qt.Key_I ? 1 : -1);
            } else if (event.key === Qt.Key_M && !shift) {
                Screenshot.lens_on = !Screenshot.lens_on;
            } else if (root.pixel_mode && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                ThemeAudio.play("confirm");
                Screenshot.pick_pixel();
            } else if ((toolbar || root.target_mode) && !Screenshot.frozen && event.key === Qt.Key_D) {
                Screenshot.cycle_delay();
            } else if (!toolbar && root.target_mode && dir) {
                Screenshot.step_target(dir[0], dir[1]);
                root.play_if_moved(before);
            } else if (!toolbar && root.target_mode && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
                Screenshot.cycle_target(event.key === Qt.Key_Backtab || shift ? -1 : 1);
                root.play_if_moved(before);
            } else if (!toolbar && root.target_mode && Style.picker_skin === "tiecomp" && event.key === Qt.Key_T && !ctrl) {
                Screenshot.cycle_target(shift ? -1 : 1);
                root.play_if_moved(before);
            } else if (!toolbar && root.target_mode && event.text !== "" && Style.picker_hint_keys.indexOf(event.text) >= 0 && Style.picker_hint_keys.indexOf(event.text) < Screenshot.targets.length) {
                Screenshot.highlight(Style.picker_hint_keys.indexOf(event.text));
                ThemeAudio.play("confirm");
                Screenshot.confirm();
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (toolbar) {
                    root.run_tool(Screenshot.tool_index);
                } else if (Screenshot.anchored || Screenshot.has_selection || root.target_mode) {
                    ThemeAudio.play("confirm");
                    Screenshot.confirm();
                } else {
                    Screenshot.select_screen(Screenshot.cursor_screen);
                    ThemeAudio.play("confirm");
                    Screenshot.confirm();
                }
            } else if (typed >= 0) {
                root.run_tool(typed);
            } else if (toolbar && event.key === Qt.Key_Backspace) {
                ThemeAudio.play("cancel");
                Screenshot.reselect();
            } else if (toolbar && dir && dir[0] !== 0) {
                Screenshot.tool_index = (Screenshot.tool_index + dir[0] + Screenshot.actions.length) % Screenshot.actions.length;
                root.play_if_moved(before);
            } else if (toolbar && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
                const delta = event.key === Qt.Key_Backtab || shift ? -1 : 1;
                Screenshot.tool_index = (Screenshot.tool_index + delta + Screenshot.actions.length) % Screenshot.actions.length;
                root.play_if_moved(before);
            } else if (!toolbar && dir) {
                keys_item.held[event.key] = dir;
                let dx = 0;
                let dy = 0;
                for (const k in keys_item.held) {
                    dx += keys_item.held[k][0];
                    dy += keys_item.held[k][1];
                }
                Screenshot.move_cursor(Math.sign(dx) * step, Math.sign(dy) * step);
            } else if (!toolbar && !root.pixel_mode && !root.target_mode && (event.key === Qt.Key_V || event.key === Qt.Key_Space)) {
                if (event.key === Qt.Key_Space && event.isAutoRepeat) {
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Space && Screenshot.anchored) {
                    ThemeAudio.play("confirm");
                    Screenshot.confirm();
                } else {
                    Screenshot.toggle_anchor();
                }
            } else if (!toolbar && !root.pixel_mode && !root.target_mode && shift && event.key === Qt.Key_O) {
                Screenshot.swap_anchor();
            } else {
                return;
            }
            event.accepted = true;
        }
    }
}
