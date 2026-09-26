// home/quickshell/.config/quickshell/components/RegionSelector.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../services"

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
    property bool help_open: false
    readonly property string delay_label: Screenshot.delay_s > 0 ? "Delay " + Screenshot.delay_s + "s" : "No delay"
    readonly property string tier_keys: "hjkl move 10px · H/J/K/L move 100px · C-hjkl move 1px · C-H/J/K/L move 300px"
    readonly property string help_text: Screenshot.phase === "toolbar" ? "h/l move · Tab/S-Tab next/prev · c copy · s save · a annotate · o ocr · r record" + (Screenshot.frozen ? "" : " · d delay off/3s/5s/10s") + " · Enter run · Backspace reselect · q/Esc cancel" : root.pixel_mode ? root.tier_keys + " · Enter pick · click pick · m loupe · +/- zoom · q/Esc cancel" : root.target_mode ? "hjkl nearest " + Screenshot.mode + " · Tab/S-Tab cycle · d delay off/3s/5s/10s · Enter pick · click pick · m loupe · +/- zoom · q/Esc cancel" : root.tier_keys + " · v/space set or drop anchor · o swap ends · drag select · Enter confirm, whole screen without a selection · m loupe · +/- zoom · Esc drop anchor, then cancel · q cancel"

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
    WlrLayershell.keyboardFocus: root.keyboard_owner ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property point press_point: Qt.point(0, 0)
    property point last_mouse: Qt.point(-1, -1)

    function run_tool(index) {
        const action = Screenshot.actions[index];
        if (action) Screenshot.act(action.id);
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
                visible: modelData.screen === root.screen_name && index !== Screenshot.target_index && Screenshot.phase === "select"
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
            visible: root.mine
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

        Rectangle {
            id: readout
            visible: root.mine
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
            visible: Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name && (Screenshot.keys_moved || Screenshot.anchored)

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

        Item {
            id: loupe
            readonly property real lens: 176
            readonly property real pad: 6
            readonly property int zoom: Screenshot.zoom
            // Odd, so one buffer pixel sits in the center.
            readonly property int count: Math.floor(loupe.lens / loupe.zoom) % 2 === 0 ? Math.floor(loupe.lens / loupe.zoom) + 1 : Math.floor(loupe.lens / loupe.zoom)
            readonly property int half: (loupe.count - 1) / 2
            readonly property real view: loupe.count * loupe.zoom
            readonly property point at: Screenshot.cursor_point
            readonly property int bx: Math.floor(loupe.at.x * root.sample_scale)
            readonly property int by: Math.floor(loupe.at.y * root.sample_scale)
            readonly property real gap: 28
            visible: Screenshot.lens_on && Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name && (root.pixel_mode ? root.frame_ready : frozen_view.hasContent)
            width: loupe.view + loupe.pad * 2
            height: loupe.view + loupe.pad * 2 + coords.implicitHeight + 4 + (root.pixel_mode ? swatch_row.height + 4 : 0)
            x: loupe.at.x + loupe.gap + loupe.width <= root.width ? loupe.at.x + loupe.gap : loupe.at.x - loupe.gap - loupe.width
            y: loupe.at.y + loupe.gap + loupe.height <= root.height ? loupe.at.y + loupe.gap : loupe.at.y - loupe.gap - loupe.height

            Rectangle {
                anchors.fill: parent
                radius: Style.frame_radius
                color: Style.frame_color
                border.width: Math.max(1, Style.frame_border_width)
                border.color: Style.frame_border_color
            }

            Item {
                x: loupe.pad
                y: loupe.pad
                width: loupe.view
                height: loupe.view
                clip: true

                Image {
                    visible: root.pixel_mode
                    anchors.fill: parent
                    source: root.pixel_mode ? root.pixel_image : ""
                    sourceClipRect: Qt.rect(loupe.bx - loupe.half, loupe.by - loupe.half, loupe.count, loupe.count)
                    cache: false
                    smooth: false
                }

                ShaderEffectSource {
                    visible: !root.pixel_mode
                    anchors.fill: parent
                    sourceItem: root.pixel_mode ? null : frozen_view
                    sourceRect: Qt.rect((loupe.bx - loupe.half) / root.buffer_scale, (loupe.by - loupe.half) / root.buffer_scale, loupe.count / root.buffer_scale, loupe.count / root.buffer_scale)
                    textureSize: Qt.size(loupe.count, loupe.count)
                    smooth: false
                    mipmap: false
                }

                Repeater {
                    model: loupe.visible && loupe.zoom >= 8 ? loupe.count + 1 : 0

                    Item {
                        id: grid_line
                        required property int index
                        anchors.fill: parent

                        Rectangle {
                            x: grid_line.index * loupe.zoom
                            width: 1
                            height: parent.height
                            color: Qt.alpha(Theme.bg_shadow, 0.35)
                        }

                        Rectangle {
                            y: grid_line.index * loupe.zoom
                            width: parent.width
                            height: 1
                            color: Qt.alpha(Theme.bg_shadow, 0.35)
                        }
                    }
                }

                Rectangle {
                    x: loupe.half * loupe.zoom - border.width
                    y: loupe.half * loupe.zoom - border.width
                    width: loupe.zoom + border.width * 2
                    height: loupe.zoom + border.width * 2
                    color: "transparent"
                    border.width: loupe.zoom >= 8 ? 2 : 1
                    border.color: Style.caret_color
                }
            }

            Row {
                id: swatch_row
                visible: root.pixel_mode
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: coords.top
                anchors.bottomMargin: 2
                height: Math.max(swatch.height, hex_text.implicitHeight)
                spacing: 6

                // Draws the centre buffer pixel and reads it back as the hex readout.
                Canvas {
                    id: swatch
                    readonly property string src: root.pixel_image
                    readonly property int bx: loupe.bx
                    readonly property int by: loupe.by
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    onSrcChanged: if (swatch.src !== "") swatch.loadImage(swatch.src)
                    onImageLoaded: swatch.requestPaint()
                    onBxChanged: swatch.requestPaint()
                    onByChanged: swatch.requestPaint()
                    onPaint: {
                        const ctx = swatch.getContext("2d");
                        ctx.clearRect(0, 0, swatch.width, swatch.height);
                        const w = frame_image.sourceSize.width;
                        const h = frame_image.sourceSize.height;
                        if (swatch.src === "" || !swatch.isImageLoaded(swatch.src) || w <= 0 || h <= 0) return;
                        ctx.drawImage(swatch.src, Math.max(0, Math.min(w - 1, swatch.bx)), Math.max(0, Math.min(h - 1, swatch.by)), 1, 1, 0, 0, swatch.width, swatch.height);
                        const d = ctx.getImageData(swatch.width / 2, swatch.height / 2, 1, 1).data;
                        if (root.screen_name !== Screenshot.cursor_screen) return;
                        Screenshot.pixel_hex = "#" + [d[0], d[1], d[2]].map(v => v.toString(16).padStart(2, "0")).join("");
                        Screenshot.pixel_hex_screen = root.screen_name;
                        Screenshot.pixel_hex_point = loupe.at;
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.width: 1
                        border.color: Style.frame_border_color
                    }
                }

                Text {
                    id: hex_text
                    anchors.verticalCenter: parent.verticalCenter
                    text: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------"
                    color: Style.text_fg
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-3)
                }
            }

            Text {
                id: coords
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: loupe.pad - 2
                text: Math.round(root.modelData.x + loupe.at.x) + ", " + Math.round(root.modelData.y + loupe.at.y) + "  " + loupe.zoom + "x"
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-4)
            }
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
                text: (root.target_mode && Screenshot.phase === "select" ? "hjkl/Tab " + Screenshot.mode + " · d " + root.delay_label.toLowerCase() + " · Enter pick · Esc cancel" : root.pixel_mode ? "hjkl move · Enter pick · m loupe · +/- zoom · Esc cancel" : Screenshot.phase === "toolbar" ? "h/l move · Enter run · c copy · s save · a annotate · o ocr · r record" + (Screenshot.frozen ? "" : " · d delay") + " · Backspace reselect · Esc cancel" : Screenshot.anchored ? "hjkl extend · o swap ends · v drop anchor · Enter " + (Screenshot.preset !== "" ? Screenshot.preset : "confirm") + " · Esc drop anchor" : "drag/hjkl cursor · v/space anchor · Enter full screen · m loupe · +/- zoom · Esc cancel") + " · ? help"
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: Screenshot.phase === "select" || Screenshot.phase === "toolbar"
        cursorShape: Qt.CrossCursor
        hoverEnabled: true
        onWheel: wheel => Screenshot.step_zoom(wheel.angleDelta.y > 0 ? 1 : wheel.angleDelta.y < 0 ? -1 : 0)
        onPressed: mouse => {
            if (root.target_mode) {
                const i = Screenshot.target_at(root.screen_name, mouse.x, mouse.y);
                if (i < 0) return;
                Screenshot.phase = "select";
                Screenshot.highlight(i);
                Screenshot.confirm();
                return;
            }
            if (root.pixel_mode) {
                if (!root.frame_ready) return;
                Screenshot.set_cursor(root.screen_name, mouse.x, mouse.y, false);
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
            if (mouse.x === root.last_mouse.x && mouse.y === root.last_mouse.y && !pressed) return;
            root.last_mouse = Qt.point(mouse.x, mouse.y);
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
            if (Screenshot.has_selection) Screenshot.confirm();
            else Screenshot.sel_screen = "";
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
                if (!toolbar && Screenshot.anchored) Screenshot.clear_anchor();
                else Screenshot.cancel();
            } else if (event.key === Qt.Key_Q) {
                Screenshot.cancel();
            } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.text === "+" || event.text === "=") {
                Screenshot.step_zoom(1);
            } else if (event.key === Qt.Key_Minus || event.text === "-") {
                Screenshot.step_zoom(-1);
            } else if (event.key === Qt.Key_M && !shift) {
                Screenshot.lens_on = !Screenshot.lens_on;
            } else if (root.pixel_mode && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                Screenshot.pick_pixel();
            } else if ((toolbar || root.target_mode) && !Screenshot.frozen && event.key === Qt.Key_D) {
                Screenshot.cycle_delay();
            } else if (!toolbar && root.target_mode && dir) {
                Screenshot.step_target(dir[0], dir[1]);
            } else if (!toolbar && root.target_mode && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
                Screenshot.cycle_target(event.key === Qt.Key_Backtab || shift ? -1 : 1);
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (toolbar) root.run_tool(Screenshot.tool_index);
                else if (Screenshot.anchored || Screenshot.has_selection || root.target_mode) Screenshot.confirm();
                else {
                    Screenshot.select_screen(root.screen_name);
                    Screenshot.confirm();
                }
            } else if (typed >= 0) {
                root.run_tool(typed);
            } else if (toolbar && event.key === Qt.Key_Backspace) {
                Screenshot.phase = "select";
            } else if (toolbar && dir && dir[0] !== 0) {
                Screenshot.tool_index = (Screenshot.tool_index + dir[0] + Screenshot.actions.length) % Screenshot.actions.length;
            } else if (toolbar && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
                const delta = event.key === Qt.Key_Backtab || shift ? -1 : 1;
                Screenshot.tool_index = (Screenshot.tool_index + delta + Screenshot.actions.length) % Screenshot.actions.length;
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
                Screenshot.toggle_anchor();
            } else if (!toolbar && !root.pixel_mode && !root.target_mode && event.key === Qt.Key_O) {
                Screenshot.swap_anchor();
            } else {
                return;
            }
            event.accepted = true;
        }
    }
}
