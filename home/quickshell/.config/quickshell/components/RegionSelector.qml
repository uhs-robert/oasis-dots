// home/quickshell/.config/quickshell/components/RegionSelector.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../services"
import "picker"
import "snes" as SnesParts

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
    readonly property bool skinned_targets: ["scope", "jrpg", "goldeneye", "scopeitem", "scanvisor"].includes(Style.picker_skin)
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
    // Exclusive would make Hyprland send every screen's pointer input to this one surface.
    WlrLayershell.keyboardFocus: root.keyboard_owner ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

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

        ScopeTargets {
            anchors.fill: parent
            visible: Style.picker_skin === "scope" && !root.pixel_mode
            screen_name: root.screen_name
            sel: root.sel
            mine: root.mine
            target_mode: root.target_mode
        }

        JrpgTargets {
            anchors.fill: parent
            visible: Style.picker_skin === "jrpg" && !root.pixel_mode
            screen_name: root.screen_name
            sel: root.sel
            mine: root.mine
            target_mode: root.target_mode
        }

        LockOnTargets {
            anchors.fill: parent
            visible: Style.picker_skin === "goldeneye" && !root.pixel_mode
            screen_name: root.screen_name
            sel: root.sel
            mine: root.mine
            target_mode: root.target_mode
        }

        ScopeItemTargets {
            anchors.fill: parent
            visible: Style.picker_skin === "scopeitem" && !root.pixel_mode
            screen_name: root.screen_name
            sel: root.sel
            mine: root.mine
            target_mode: root.target_mode
            origin: Qt.point(root.modelData.x, root.modelData.y)
        }

        ScanVisorTargets {
            anchors.fill: parent
            visible: Style.picker_skin === "scanvisor" && !root.pixel_mode
            screen_name: root.screen_name
            origin: Qt.point(root.modelData.x, root.modelData.y)
            sel: root.sel
            mine: root.mine
            target_mode: root.target_mode
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
            readonly property bool hide_arms: Style.picker_skin !== "" && !root.target_mode
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

        ScopeCursor {
            anchors.fill: parent
            screen_name: root.screen_name
            origin: Qt.point(root.modelData.x, root.modelData.y)
            target_mode: root.target_mode
        }

        JrpgCursor {
            anchors.fill: parent
            screen_name: root.screen_name
            target_mode: root.target_mode
        }

        LockOnCursor {
            anchors.fill: parent
            screen_name: root.screen_name
            target_mode: root.target_mode
        }

        ScopeItemCursor {
            anchors.fill: parent
            screen_name: root.screen_name
            origin: Qt.point(root.modelData.x, root.modelData.y)
            target_mode: root.target_mode
        }

        ScanVisorCursor {
            id: scan_cursor
            anchors.fill: parent
            screen_name: root.screen_name
            target_mode: root.target_mode
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
            readonly property bool scope: Style.picker_skin === "scope"
            readonly property bool jrpg: Style.picker_skin === "jrpg"
            readonly property bool goldeneye: Style.picker_skin === "goldeneye"
            readonly property bool scopeitem: Style.picker_skin === "scopeitem"
            readonly property bool scanvisor: Style.picker_skin === "scanvisor"
            readonly property real gap: loupe.scanvisor ? 40 : loupe.scope || loupe.jrpg || loupe.goldeneye || loupe.scopeitem ? 36 : 28
            readonly property real jrpg_name_h: 16
            readonly property real jrpg_gap: 6
            readonly property real jrpg_drop: 3
            readonly property real ge_rim: 208
            readonly property real ge_strip_gap: 8
            readonly property real ge_strip_h: 52
            readonly property real si_pad: 10
            readonly property real si_ruler_h: 22
            readonly property real si_zbar_w: 30
            readonly property real si_body_gap: 10
            readonly property real si_foot_gap: 8
            readonly property real si_foot_h: 20
            readonly property real sv_pad: 10
            readonly property real sv_header_h: 18
            readonly property real sv_header_gap: 8
            readonly property real sv_card_gap: 17
            readonly property bool sv_complete: scan_cursor.complete
            // R/G/B parsed from the swatch's hex readout; withheld as 0 until the scan completes.
            readonly property var sv_rgb: {
                if (!loupe.sv_complete) return [0, 0, 0];
                const hex = Screenshot.pixel_hex;
                if (hex.length < 7) return [0, 0, 0];
                return [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)];
            }
            // Zero-padded global coordinate readout for the watch strip.
            function ge_pad4(v) {
                const n = Math.round(v);
                return (n < 0 ? "-" : "") + String(Math.abs(n)).padStart(4, "0");
            }
            // R/G/B in pixel mode; X/Y (and W/H while dragging) in region mode, values matching the coords readout.
            readonly property var jrpg_rows: {
                if (!loupe.jrpg) return [];
                if (root.pixel_mode) {
                    const hex = Screenshot.pixel_hex;
                    const rgb = hex.length >= 7 ? [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)] : [0, 0, 0];
                    return [
                        { label: "R", value: rgb[0], ratio: rgb[0] / 255, color: Theme.red },
                        { label: "G", value: rgb[1], ratio: rgb[1] / 255, color: Theme.green },
                        { label: "B", value: rgb[2], ratio: rgb[2] / 255, color: Theme.blue }
                    ];
                }
                const rows = [
                    { label: "X", value: Math.round(root.modelData.x + loupe.at.x), ratio: loupe.at.x / root.width, color: Theme.theme_primary_light },
                    { label: "Y", value: Math.round(root.modelData.y + loupe.at.y), ratio: loupe.at.y / root.height, color: Theme.theme_primary_light }
                ];
                if (root.mine) {
                    rows.push({ label: "W", value: Math.round(root.sel.width), ratio: root.sel.width / root.width, color: Theme.theme_secondary });
                    rows.push({ label: "H", value: Math.round(root.sel.height), ratio: root.sel.height / root.height, color: Theme.theme_secondary });
                }
                return rows;
            }
            readonly property real jrpg_stats_h: loupe.jrpg_rows.length > 0 ? loupe.jrpg_rows.length * 14 + (loupe.jrpg_rows.length - 1) * 3 : 0
            readonly property real header_h: loupe.scope ? 20 : loupe.jrpg ? loupe.jrpg_name_h + loupe.jrpg_gap : loupe.scopeitem ? loupe.si_ruler_h : 0
            readonly property real foot_h: 22
            readonly property real si_body_w: loupe.view + loupe.si_body_gap + loupe.si_zbar_w
            visible: Screenshot.lens_on && Screenshot.phase === "select" && Screenshot.cursor_screen === root.screen_name && (root.pixel_mode ? root.frame_ready : frozen_view.hasContent)
            width: loupe.goldeneye ? loupe.ge_rim : loupe.scopeitem ? loupe.si_pad * 2 + loupe.si_body_w : loupe.scanvisor ? loupe.sv_pad * 2 + loupe.view : loupe.view + loupe.pad * 2 + (loupe.jrpg ? loupe.jrpg_drop : 0)
            height: loupe.goldeneye ? loupe.ge_rim + loupe.ge_strip_gap + loupe.ge_strip_h : loupe.scope ? loupe.view + loupe.pad * 2 + loupe.header_h + loupe.foot_h : loupe.jrpg ? loupe.pad + loupe.header_h + loupe.view + loupe.jrpg_gap + loupe.jrpg_stats_h + loupe.pad + loupe.jrpg_drop : loupe.scopeitem ? loupe.si_pad + loupe.si_ruler_h + loupe.view + loupe.si_foot_gap + loupe.si_foot_h + loupe.si_pad : loupe.scanvisor ? loupe.sv_pad + loupe.sv_header_h + loupe.sv_header_gap + loupe.view + loupe.sv_card_gap + sv_card_col.implicitHeight + loupe.sv_pad : loupe.view + loupe.pad * 2 + coords.implicitHeight + 4 + (root.pixel_mode ? swatch_row.height + 4 : 0)
            x: loupe.at.x + loupe.gap + loupe.width <= root.width ? loupe.at.x + loupe.gap : loupe.at.x - (loupe.jrpg ? 66 : loupe.gap) - loupe.width
            y: loupe.at.y + loupe.gap + loupe.height <= root.height ? loupe.at.y + loupe.gap : loupe.at.y - loupe.gap - loupe.height

            Rectangle {
                visible: !loupe.scope && !loupe.jrpg && !loupe.goldeneye && !loupe.scopeitem && !loupe.scanvisor
                anchors.fill: parent
                radius: Style.frame_radius
                color: Style.frame_color
                border.width: Math.max(1, Style.frame_border_width)
                border.color: Style.frame_border_color
            }

            ScanGlass {
                visible: loupe.scanvisor
                anchors.fill: parent
                corner: 12
                sheen: true
            }

            Rectangle {
                visible: loupe.scope
                anchors.fill: parent
                radius: 0
                color: Qt.alpha(Style.frame_color, 0.82)
                border.width: 1
                border.color: Qt.alpha(Style.picker_hud, 0.7)
            }

            Rectangle {
                visible: loupe.scopeitem
                anchors.fill: parent
                radius: 6
                border.width: 1
                border.color: Qt.alpha(Theme.blue, 0.65)
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.blue, 0.16))
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Theme.bg_crust, 0.9)
                    }
                }
            }

            Rectangle {
                visible: loupe.scopeitem
                x: 1
                y: 1
                width: parent.width - 2
                height: 1
                color: Qt.alpha(Theme.fg_strong, 0.18)
            }

            SnesParts.SnesWindow {
                visible: loupe.jrpg
                anchors.fill: parent
            }

            MultiEffect {
                visible: loupe.goldeneye
                anchors.fill: ge_rim_item
                source: ge_rim_item
                shadowEnabled: true
                shadowColor: Qt.alpha(Theme.bg_shadow, 0.6)
                shadowHorizontalOffset: 4
                shadowVerticalOffset: 6
                shadowBlur: 0.4
            }

            Item {
                id: ge_rim_item
                visible: loupe.goldeneye
                layer.enabled: loupe.goldeneye
                x: 0
                y: 0
                width: loupe.ge_rim
                height: loupe.ge_rim

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Theme.bg_crust
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 10
                    height: parent.height - 10
                    radius: width / 2
                    color: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.bg_crust, 0.5))
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 14
                    height: parent.height - 14
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(Theme.fg_strong, 0.12)
                }

                Text {
                    anchors.top: parent.top
                    anchors.topMargin: 14
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "x" + loupe.zoom + ".0"
                    color: Theme.theme_label
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                }
            }

            Text {
                id: jrpg_name_left
                visible: loupe.jrpg
                x: loupe.pad
                y: loupe.pad
                text: root.pixel_mode ? (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") : "TARGET"
                color: Theme.fg_strong
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }

            Text {
                id: jrpg_name_right
                visible: loupe.jrpg
                x: loupe.pad + loupe.view - jrpg_name_right.implicitWidth
                y: loupe.pad
                text: "Lv " + loupe.zoom
                color: Theme.theme_secondary
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
            }

            Text {
                id: zoomhead
                visible: loupe.scope
                anchors.top: parent.top
                anchors.topMargin: 6
                anchors.horizontalCenter: parent.horizontalCenter
                text: "- ZOOM LEVEL - -  " + loupe.zoom * 100 + " -"
                color: Style.picker_hud
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
            }

            Item {
                id: si_ruler
                visible: loupe.scopeitem
                x: loupe.si_pad
                y: loupe.si_pad
                width: loupe.si_body_w
                height: loupe.si_ruler_h
                clip: true

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Qt.alpha(Theme.blue, 0.6)
                }

                Shape {
                    id: si_caret
                    x: parent.width / 2 - 5
                    y: 0
                    width: 10
                    height: 5
                    ShapePath {
                        fillColor: Theme.theme_secondary
                        strokeWidth: -1
                        startX: 0
                        startY: 0
                        PathLine {
                            x: 10
                            y: 0
                        }
                        PathLine {
                            x: 5
                            y: 5
                        }
                        PathLine {
                            x: 0
                            y: 0
                        }
                    }
                }

                Repeater {
                    model: si_ruler.visible ? Math.ceil(si_ruler.width / 40) + 2 : 0

                    Text {
                        id: si_tick
                        required property int index
                        readonly property real step: 40
                        readonly property real base_x: Math.round(root.modelData.x + loupe.at.x)
                        readonly property real first: Math.ceil((si_tick.base_x - si_ruler.width / 2) / si_tick.step) * si_tick.step
                        readonly property real global_v: si_tick.first + si_tick.index * si_tick.step
                        x: si_ruler.width / 2 + (si_tick.global_v - si_tick.base_x) - si_tick.implicitWidth / 2
                        y: si_ruler.height - si_tick.implicitHeight - 5
                        text: (si_tick.global_v < 0 ? "-" : "") + String(Math.abs(Math.round(si_tick.global_v))).padStart(4, "0")
                        color: Theme.theme_primary_light
                        font.family: Style.mono_font
                        font.pixelSize: Style.fs(-8)

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: 1
                            width: 1
                            height: 4
                            color: Theme.blue
                        }
                    }
                }
            }

            Item {
                id: lens_content
                x: loupe.goldeneye ? (loupe.ge_rim - loupe.view) / 2 : loupe.scopeitem ? loupe.si_pad : loupe.scanvisor ? loupe.sv_pad : loupe.pad
                y: loupe.goldeneye ? (loupe.ge_rim - loupe.view) / 2 : loupe.scopeitem ? loupe.si_pad + loupe.si_ruler_h : loupe.scanvisor ? loupe.sv_pad + loupe.sv_header_h + loupe.sv_header_gap : loupe.pad + loupe.header_h
                width: loupe.view
                height: loupe.view
                clip: true
                visible: !loupe.goldeneye
                layer.enabled: loupe.goldeneye

                ShaderEffectSource {
                    anchors.fill: parent
                    sourceItem: root.pixel_mode ? frame_image : frozen_view
                    sourceRect: Qt.rect((loupe.bx - loupe.half) / root.sample_scale, (loupe.by - loupe.half) / root.sample_scale, loupe.count / root.sample_scale, loupe.count / root.sample_scale)
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
                            color: loupe.scanvisor ? Qt.alpha(Theme.cyan, 0.14) : Qt.alpha(Theme.bg_shadow, 0.35)
                        }

                        Rectangle {
                            y: grid_line.index * loupe.zoom
                            width: parent.width
                            height: 1
                            color: loupe.scanvisor ? Qt.alpha(Theme.cyan, 0.14) : Qt.alpha(Theme.bg_shadow, 0.35)
                        }
                    }
                }

                Repeater {
                    model: loupe.scope ? Math.ceil(loupe.view / 3) : 0

                    Rectangle {
                        required property int index
                        y: index * 3
                        width: loupe.view
                        height: 1
                        color: Qt.rgba(0, 0, 0, 0.18)
                    }
                }

                Repeater {
                    model: loupe.scopeitem ? Math.ceil(loupe.view / 3) : 0

                    Rectangle {
                        required property int index
                        y: index * 3
                        width: loupe.view
                        height: 1
                        color: Qt.alpha(Theme.bg_shadow, 0.14)
                    }
                }

                Rectangle {
                    visible: loupe.scopeitem
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(Theme.blue, 0.55)
                }

                CornerBrackets {
                    visible: loupe.scopeitem
                    anchors.fill: parent
                    color: Theme.blue
                    inset: 6
                    arm: 14
                    thickness: 2
                    all_corners: true
                }

                Repeater {
                    model: loupe.scope ? Math.floor(loupe.view / 11) + 1 : 0

                    Rectangle {
                        required property int index
                        x: loupe.view - 3
                        y: index * 11
                        width: 3
                        height: 1
                        color: Qt.alpha(Style.picker_hud, 0.7)
                    }
                }

                Rectangle {
                    visible: loupe.scope
                    x: 0
                    y: center_px.y + center_px.height / 2
                    width: Math.max(0, center_px.x)
                    height: 1
                    color: Qt.alpha(Style.picker_hud, 0.45)
                }

                Rectangle {
                    visible: loupe.scope
                    x: center_px.x + center_px.width
                    y: center_px.y + center_px.height / 2
                    width: Math.max(0, loupe.view - x)
                    height: 1
                    color: Qt.alpha(Style.picker_hud, 0.45)
                }

                Rectangle {
                    visible: loupe.scope
                    x: center_px.x + center_px.width / 2
                    y: 0
                    width: 1
                    height: Math.max(0, center_px.y)
                    color: Qt.alpha(Style.picker_hud, 0.45)
                }

                Rectangle {
                    visible: loupe.scope
                    x: center_px.x + center_px.width / 2
                    y: center_px.y + center_px.height
                    width: 1
                    height: Math.max(0, loupe.view - y)
                    color: Qt.alpha(Style.picker_hud, 0.45)
                }

                Canvas {
                    id: ge_vignette
                    visible: loupe.goldeneye
                    anchors.fill: parent
                    onPaint: {
                        const ctx = ge_vignette.getContext("2d");
                        ctx.clearRect(0, 0, ge_vignette.width, ge_vignette.height);
                        const cx2 = ge_vignette.width / 2;
                        const cy2 = ge_vignette.height / 2;
                        const r = Math.max(cx2, cy2);
                        const grad = ctx.createRadialGradient(cx2, cy2, r * 0.62, cx2, cy2, r);
                        grad.addColorStop(0, Qt.alpha(Theme.bg_shadow, 0));
                        grad.addColorStop(1, Qt.alpha(Theme.bg_shadow, 1));
                        ctx.fillStyle = grad;
                        ctx.fillRect(0, 0, ge_vignette.width, ge_vignette.height);
                    }
                    Component.onCompleted: ge_vignette.requestPaint()
                }

                Rectangle {
                    visible: loupe.goldeneye
                    x: 0
                    y: center_px.y + center_px.height / 2
                    width: Math.max(0, center_px.x - 3)
                    height: 1
                    color: Theme.bg_shadow
                }

                Rectangle {
                    visible: loupe.goldeneye
                    x: center_px.x + center_px.width + 3
                    y: center_px.y + center_px.height / 2
                    width: Math.max(0, loupe.view - x)
                    height: 1
                    color: Theme.bg_shadow
                }

                Rectangle {
                    visible: loupe.goldeneye
                    x: center_px.x + center_px.width / 2
                    y: 0
                    width: 1
                    height: Math.max(0, center_px.y - 3)
                    color: Theme.bg_shadow
                }

                Rectangle {
                    visible: loupe.goldeneye
                    x: center_px.x + center_px.width / 2
                    y: center_px.y + center_px.height + 3
                    width: 1
                    height: Math.max(0, loupe.view - y)
                    color: Theme.bg_shadow
                }

                Rectangle {
                    visible: loupe.goldeneye
                    x: 0
                    y: (loupe.view - 30) / 2
                    width: 3
                    height: 30
                    color: Theme.bg_shadow
                }

                Rectangle {
                    visible: loupe.goldeneye
                    x: loupe.view - 3
                    y: (loupe.view - 30) / 2
                    width: 3
                    height: 30
                    color: Theme.bg_shadow
                }

                Rectangle {
                    visible: loupe.goldeneye
                    x: (loupe.view - 30) / 2
                    y: loupe.view - 3
                    width: 30
                    height: 3
                    color: Theme.bg_shadow
                }

                Rectangle {
                    id: center_px
                    x: loupe.half * loupe.zoom - border.width
                    y: loupe.half * loupe.zoom - border.width
                    width: loupe.zoom + border.width * 2
                    height: loupe.zoom + border.width * 2
                    color: "transparent"
                    border.width: loupe.zoom >= 8 ? 2 : 1
                    border.color: loupe.scope ? Style.picker_hud : loupe.jrpg ? (jrpg_blink.alt ? Theme.theme_secondary : Theme.fg_strong) : loupe.goldeneye ? Theme.theme_label : loupe.scopeitem ? Theme.theme_secondary : loupe.scanvisor ? (loupe.sv_complete ? Theme.bright_green : Theme.bright_yellow) : Style.caret_color
                }

                Rectangle {
                    visible: loupe.jrpg
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.theme_primary_light
                }
            }

            Rectangle {
                id: ge_lens_mask
                visible: false
                x: lens_content.x
                y: lens_content.y
                width: lens_content.width
                height: lens_content.height
                radius: width / 2
                layer.enabled: true
            }

            MultiEffect {
                visible: loupe.goldeneye
                x: lens_content.x
                y: lens_content.y
                width: lens_content.width
                height: lens_content.height
                source: lens_content
                maskEnabled: true
                maskSource: ge_lens_mask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Timer {
                id: jrpg_blink
                property bool alt: false
                running: loupe.jrpg && loupe.visible
                interval: 400
                repeat: true
                onTriggered: jrpg_blink.alt = !jrpg_blink.alt
            }

            Row {
                id: swatch_row
                visible: loupe.scope ? true : root.pixel_mode
                opacity: loupe.jrpg || loupe.goldeneye || loupe.scopeitem || loupe.scanvisor ? 0 : 1
                anchors.horizontalCenter: !loupe.scope ? parent.horizontalCenter : undefined
                anchors.bottom: !loupe.scope ? coords.top : undefined
                anchors.bottomMargin: 2
                anchors.right: loupe.scope ? scope_foot.right : undefined
                anchors.verticalCenter: loupe.scope ? scope_foot.verticalCenter : undefined
                height: Math.max(swatch.height, hex_text.implicitHeight)
                spacing: 6

                // Draws the centre buffer pixel and reads it back as the hex readout.
                Canvas {
                    id: swatch
                    visible: root.pixel_mode
                    readonly property string src: root.pixel_image
                    readonly property int bx: loupe.bx
                    readonly property int by: loupe.by
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    onSrcChanged: if (swatch.src !== "") swatch.loadImage(swatch.src)
                    onImageLoaded: swatch.requestPaint()
                    onBxChanged: Qt.callLater(swatch.requestPaint)
                    onByChanged: Qt.callLater(swatch.requestPaint)
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
                    visible: root.pixel_mode
                    anchors.verticalCenter: parent.verticalCenter
                    text: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------"
                    color: loupe.scope ? Style.picker_hud : Style.text_fg
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-3)
                }

                Text {
                    id: scope_read
                    visible: loupe.scope && !root.pixel_mode
                    anchors.verticalCenter: parent.verticalCenter
                    text: "X" + Math.round(root.modelData.x + loupe.at.x) + " Y" + Math.round(root.modelData.y + loupe.at.y)
                    color: Style.picker_hud
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-3)
                }
            }

            Text {
                id: coords
                visible: !loupe.scope && !loupe.jrpg && !loupe.goldeneye && !loupe.scopeitem && !loupe.scanvisor
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: loupe.pad - 2
                text: Math.round(root.modelData.x + loupe.at.x) + ", " + Math.round(root.modelData.y + loupe.at.y) + "  " + loupe.zoom + "x"
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-4)
            }

            Item {
                id: scope_foot
                visible: loupe.scope
                x: loupe.pad
                y: loupe.pad + loupe.header_h + loupe.view + (loupe.foot_h - foot_left.height) / 2
                width: loupe.view
                height: foot_left.height

                Row {
                    id: foot_left
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Item {
                        width: 26
                        height: 14
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            x: 1
                            y: 2
                            width: 10
                            height: 10
                            radius: 5
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.red
                        }

                        Rectangle {
                            x: 15
                            y: 2
                            width: 10
                            height: 10
                            radius: 5
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.red
                        }

                        Rectangle {
                            x: 10
                            y: 5
                            width: 6
                            height: 3
                            color: Theme.red
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pixel_mode ? "SCOPE" : "CAMERA"
                        color: Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                    }
                }
            }

            Column {
                id: si_zbar
                visible: loupe.scopeitem
                x: loupe.si_pad + loupe.view + loupe.si_body_gap
                y: loupe.si_pad + loupe.si_ruler_h + loupe.view - si_zbar.implicitHeight
                spacing: 3

                Repeater {
                    model: loupe.scopeitem ? [3, 2, 1, 0] : []

                    Rectangle {
                        id: si_seg
                        required property int modelData
                        readonly property int step: Screenshot.zoom_levels[si_seg.modelData]
                        width: loupe.si_zbar_w
                        height: 10
                        color: si_seg.step <= loupe.zoom ? Theme.blue : "transparent"
                        border.width: si_seg.step <= loupe.zoom ? 0 : 1
                        border.color: Qt.alpha(Theme.blue, 0.5)
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "x" + loupe.zoom
                    color: Theme.blue
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-7)
                }
            }

            Item {
                id: si_foot
                visible: loupe.scopeitem
                x: loupe.si_pad
                y: loupe.si_pad + loupe.si_ruler_h + loupe.view + loupe.si_foot_gap
                width: loupe.si_body_w
                height: loupe.si_foot_h

                Row {
                    id: si_chip
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: si_icon.width + 6
                        height: si_icon.height + 4
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Theme.blue, 0.5)

                        Item {
                            id: si_icon
                            anchors.centerIn: parent
                            width: 22
                            height: 11

                            Rectangle {
                                x: 0
                                y: 1
                                width: 9
                                height: 9
                                radius: 4
                                color: "transparent"
                                border.width: 2
                                border.color: Theme.blue
                            }

                            Rectangle {
                                x: 13
                                y: 1
                                width: 9
                                height: 9
                                radius: 4
                                color: "transparent"
                                border.width: 2
                                border.color: Theme.blue
                            }

                            Rectangle {
                                x: 8
                                y: 4
                                width: 6
                                height: 3
                                color: Theme.blue
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pixel_mode ? "SCOPE" : "CAMERA"
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.bold: true
                        font.letterSpacing: 1
                        font.pixelSize: Style.fs(-6)
                    }
                }

                Row {
                    id: si_pixel_read
                    visible: root.pixel_mode
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12
                        height: 12
                        color: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Theme.blue, 0.5)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------"
                        color: Theme.fg_strong
                        font.family: Style.mono_font
                        font.pixelSize: Style.fs(-4)
                    }
                }

                Text {
                    visible: !root.pixel_mode
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mine ? Math.round(root.sel.width) + " x " + Math.round(root.sel.height) : loupe.ge_pad4(root.modelData.x + loupe.at.x) + " " + loupe.ge_pad4(root.modelData.y + loupe.at.y)
                    color: Theme.fg_strong
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-4)
                }
            }

            Column {
                id: jrpg_stats
                visible: loupe.jrpg
                x: loupe.pad
                y: loupe.pad + loupe.header_h + loupe.view + loupe.jrpg_gap
                width: loupe.view
                spacing: 3

                Repeater {
                    model: loupe.jrpg ? loupe.jrpg_rows : []

                    Item {
                        id: stat_row
                        required property var modelData
                        width: jrpg_stats.width
                        height: 14

                        Text {
                            id: stat_label
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            text: stat_row.modelData.label
                            color: Theme.theme_primary_light
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-7)
                        }

                        Text {
                            id: stat_value
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            horizontalAlignment: Text.AlignRight
                            text: String(stat_row.modelData.value)
                            color: Theme.fg_strong
                            font.family: Style.mono_font
                            font.pixelSize: Style.fs(-7)
                        }

                        Rectangle {
                            anchors.left: stat_label.right
                            anchors.leftMargin: 4
                            anchors.right: stat_value.left
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            height: 6
                            color: Theme.bg_shadow
                            border.width: 1
                            border.color: Theme.fg_muted

                            Rectangle {
                                x: 1
                                y: 1
                                width: Math.max(0, (parent.width - 2) * Math.max(0, Math.min(1, stat_row.modelData.ratio)))
                                height: parent.height - 2
                                color: stat_row.modelData.color
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: ge_strip
                visible: loupe.goldeneye
                x: (loupe.ge_rim - loupe.view) / 2
                y: loupe.ge_rim + loupe.ge_strip_gap
                width: loupe.view
                height: loupe.ge_strip_h
                radius: 12
                border.width: 2
                border.color: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_muted, 0.4))
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Theme.bg_surface
                    }
                    GradientStop {
                        position: 1
                        color: Theme.bg_mantle
                    }
                }

                layer.enabled: loupe.goldeneye
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.alpha(Theme.bg_shadow, 0.6)
                    shadowHorizontalOffset: 4
                    shadowVerticalOffset: 6
                    shadowBlur: 0.4
                }

                Text {
                    x: 10
                    y: 6
                    text: "Q-BRANCH"
                    color: Theme.fg_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-7)
                }

                Text {
                    id: ge_strip_right_label
                    x: parent.width - width - 10
                    y: 6
                    text: root.pixel_mode ? "COLOR" : "CAMERA"
                    color: Theme.fg_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-7)
                }

                Rectangle {
                    id: ge_lcd
                    x: 6
                    y: 20
                    width: parent.width - 12
                    height: parent.height - 26
                    radius: 6
                    color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.theme_primary_light, 0.14))

                    Rectangle {
                        visible: root.pixel_mode
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12
                        height: 12
                        border.width: 1
                        border.color: Theme.fg_muted
                        color: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "transparent"
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: root.pixel_mode ? 24 : 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pixel_mode ? (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") : root.mine ? Math.round(root.sel.width) + " x " + Math.round(root.sel.height) : "READY"
                        color: Theme.theme_primary_light
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-3)
                    }

                    Column {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            text: "X " + loupe.ge_pad4(root.modelData.x + loupe.at.x)
                            color: Qt.alpha(Theme.fg_dim, 0.65)
                            font.family: Style.mono_font
                            font.pixelSize: Style.fs(-7)
                        }

                        Text {
                            text: "Y " + loupe.ge_pad4(root.modelData.y + loupe.at.y)
                            color: Qt.alpha(Theme.fg_dim, 0.65)
                            font.family: Style.mono_font
                            font.pixelSize: Style.fs(-7)
                        }
                    }
                }
            }

            Item {
                id: sv_header
                visible: loupe.scanvisor
                x: loupe.sv_pad
                y: loupe.sv_pad
                width: loupe.view
                height: loupe.sv_header_h

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SCAN VISOR"
                    color: Theme.bright_cyan
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                    font.letterSpacing: 1.5
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Repeater {
                        model: loupe.scanvisor ? Screenshot.zoom_levels : []

                        Rectangle {
                            id: sv_tank
                            required property int modelData
                            width: 9
                            height: 9
                            color: sv_tank.modelData <= loupe.zoom ? Theme.bright_cyan : "transparent"
                            border.width: 1
                            border.color: Theme.bright_cyan
                        }
                    }
                }
            }

            Item {
                id: sv_card
                visible: loupe.scanvisor
                readonly property real lens_bottom: loupe.sv_pad + loupe.sv_header_h + loupe.sv_header_gap + loupe.view
                x: loupe.sv_pad
                y: sv_card.lens_bottom + loupe.sv_card_gap
                width: loupe.view

                Rectangle {
                    x: 0
                    y: -(loupe.sv_card_gap - 6)
                    width: parent.width
                    height: 1
                    color: Qt.alpha(Theme.bright_cyan, 0.25)
                }

                Column {
                    id: sv_card_col
                    width: sv_card.width
                    spacing: 4

                    Text {
                        text: root.pixel_mode ? (loupe.sv_complete ? "LOGBOOK // PIGMENT" : "SCANNING " + Math.round(scan_cursor.scan_step / scan_cursor.scan_steps * 100) + "%") : "LOGBOOK // AREA"
                        color: root.pixel_mode ? (loupe.sv_complete ? Theme.bright_green : Theme.bright_yellow) : Theme.bright_green
                        font.family: Style.font_family
                        font.pixelSize: 10
                        font.letterSpacing: 1.5
                    }

                    Row {
                        visible: root.pixel_mode
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            border.width: 1
                            border.color: Theme.fg_muted
                            color: loupe.sv_complete && Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "transparent"
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: loupe.sv_complete && Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------"
                            color: Theme.fg_strong
                            font.family: Style.number_font
                            font.pixelSize: Style.fs(-3)
                        }
                    }

                    Text {
                        visible: !root.pixel_mode
                        text: root.mine ? Math.round(root.sel.width) + " x " + Math.round(root.sel.height) : loupe.ge_pad4(root.modelData.x + loupe.at.x) + " " + loupe.ge_pad4(root.modelData.y + loupe.at.y)
                        color: Theme.fg_strong
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-3)
                    }

                    Repeater {
                        model: root.pixel_mode ? [{ label: "R", value: loupe.sv_rgb[0], color: Theme.red }, { label: "G", value: loupe.sv_rgb[1], color: Theme.bright_green }, { label: "B", value: loupe.sv_rgb[2], color: Theme.blue }] : []

                        Item {
                            id: sv_row
                            required property var modelData
                            width: sv_card_col.width
                            height: 12

                            Text {
                                id: sv_row_label
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10
                                text: sv_row.modelData.label
                                color: Theme.fg_dim
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-7)
                            }

                            Text {
                                id: sv_row_value
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                horizontalAlignment: Text.AlignRight
                                text: loupe.sv_complete ? String(sv_row.modelData.value) : "---"
                                color: Theme.fg_strong
                                font.family: Style.mono_font
                                font.pixelSize: Style.fs(-7)
                            }

                            Rectangle {
                                anchors.left: sv_row_label.right
                                anchors.leftMargin: 4
                                anchors.right: sv_row_value.left
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                height: 4
                                color: Qt.alpha(Theme.bg_shadow, 0.7)
                                border.width: 1
                                border.color: Qt.alpha(sv_row.modelData.color, 0.4)

                                Rectangle {
                                    x: 1
                                    y: 1
                                    width: Math.max(0, (parent.width - 2) * (loupe.sv_complete ? sv_row.modelData.value / 255 : 0))
                                    height: parent.height - 2
                                    color: sv_row.modelData.color
                                }
                            }
                        }
                    }

                    Text {
                        text: root.pixel_mode ? "POS " + loupe.ge_pad4(root.modelData.x + loupe.at.x) + " " + loupe.ge_pad4(root.modelData.y + loupe.at.y) : root.mine ? "FRAMING" : "STANDBY"
                        color: Theme.fg_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-7)
                    }
                }
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
        cursorShape: Style.picker_skin !== "" && Screenshot.phase === "select" && !root.target_mode && root.chrome_shown ? Qt.BlankCursor : Qt.CrossCursor
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
                    Screenshot.select_screen(Screenshot.cursor_screen);
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
