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
import "region"

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

    function set_help(open) {
        root.help_open = open;
        Qt.callLater(() => open ? overlays.focus_help() : keys_item.forceActiveFocus());
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

        SelectionChrome {
            id: chrome_layer
            sel: root.sel
            mine: root.mine
            pixel_mode: root.pixel_mode
            target_mode: root.target_mode
            skinned_targets: root.skinned_targets
            dim_color: root.dim_color
            screen_name: root.screen_name
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

        Toolbar {
            sel: root.sel
            shown: root.toolbar_shown
            readout_above: chrome_layer.readout_above
            readout_height: chrome_layer.readout_height
            delay_label: root.delay_label
            onRun: index => root.run_tool(index)
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

        KeyOverlays {
            id: overlays
            keyboard_owner: root.keyboard_owner
            help_open: root.help_open
            sharing: root.sharing
            pixel_mode: root.pixel_mode
            target_mode: root.target_mode
            delay_label: root.delay_label
            onBack: root.set_help(false)
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

    RegionKeys {
        id: keys_item
        keyboard_owner: root.keyboard_owner
        pixel_mode: root.pixel_mode
        target_mode: root.target_mode
        sharing: root.sharing
        onHelp_requested: root.set_help(true)
        onRun_tool: index => root.run_tool(index)
    }
}
