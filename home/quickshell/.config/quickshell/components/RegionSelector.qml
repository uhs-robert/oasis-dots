// home/quickshell/.config/quickshell/components/RegionSelector.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
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
    readonly property bool chrome_shown: Screenshot.phase !== "capture" && (frozen_view.hasContent || !Screenshot.frozen && root.waited)
    property bool waited: false
    // Buffer pixels per logical pixel, so the loupe magnifies real screen pixels.
    readonly property real buffer_scale: frozen_view.sourceSize.width > 0 ? frozen_view.sourceSize.width / root.width : root.modelData.devicePixelRatio
    readonly property color dim_color: Qt.alpha(Theme.bg_shadow, 0.55)

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

    function run_tool(index) {
        const action = Screenshot.actions[index];
        if (action) Screenshot.act(action.id);
    }

    // One still frame per screen: the frozen background, and the loupe's source in both modes.
    ScreencopyView {
        id: frozen_view
        anchors.fill: parent
        visible: Screenshot.frozen
        captureSource: root.modelData
        live: false
        paintCursor: false
        onStopped: if (Screenshot.frozen && !frozen_view.hasContent) Screenshot.fail("Frozen capture failed")
    }

    Timer {
        running: true
        interval: 300
        onTriggered: root.waited = true
    }

    Timer {
        running: Screenshot.frozen && !frozen_view.hasContent
        interval: 1500
        onTriggered: Screenshot.fail("Frozen capture timed out")
    }

    Item {
        id: chrome
        anchors.fill: parent
        visible: root.chrome_shown

        Rectangle {
            visible: !root.mine
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
            readonly property point at: Screenshot.lens_point
            readonly property int bx: Math.floor(loupe.at.x * root.buffer_scale)
            readonly property int by: Math.floor(loupe.at.y * root.buffer_scale)
            readonly property real gap: 28
            visible: Screenshot.lens_on && Screenshot.phase === "select" && Screenshot.lens_screen === root.screen_name && frozen_view.hasContent
            width: loupe.view + loupe.pad * 2
            height: loupe.view + loupe.pad * 2 + coords.implicitHeight + 4
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

                ShaderEffectSource {
                    anchors.fill: parent
                    sourceItem: frozen_view
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
                text: Screenshot.phase === "toolbar" ? "h/l move · Enter run · c copy · s save · a annotate · o ocr · r record · Backspace reselect · Esc cancel" : (Screenshot.has_selection ? "hjkl move · HJKL resize · Enter " + (Screenshot.preset !== "" ? Screenshot.preset : "confirm") : "drag select · Enter full screen") + " · m loupe · +/- zoom · Esc cancel"
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
            root.press_point = Qt.point(mouse.x, mouse.y);
            Screenshot.phase = "select";
            Screenshot.set_selection(root.screen_name, mouse.x, mouse.y, 0, 0);
        }
        onPositionChanged: mouse => {
            Screenshot.set_lens(root.screen_name, mouse.x, mouse.y);
            if (!pressed) return;
            const x = Math.max(0, Math.min(root.width, mouse.x));
            const y = Math.max(0, Math.min(root.height, mouse.y));
            const p = root.press_point;
            Screenshot.set_selection(root.screen_name, Math.min(p.x, x), Math.min(p.y, y), Math.abs(x - p.x), Math.abs(y - p.y));
        }
        onReleased: {
            if (Screenshot.has_selection) Screenshot.confirm();
            else Screenshot.sel_screen = "";
        }
    }

    Item {
        id: keys_item
        anchors.fill: parent
        focus: root.keyboard_owner
        Component.onCompleted: if (root.keyboard_owner) keys_item.forceActiveFocus()

        Keys.onPressed: event => {
            const shift = event.modifiers & Qt.ShiftModifier;
            const step = event.modifiers & Qt.ControlModifier ? 1 : 10;
            const toolbar = Screenshot.phase === "toolbar";
            const typed = toolbar ? Screenshot.actions.findIndex(a => a.key === event.text) : -1;
            const dir = { [Qt.Key_H]: [-1, 0], [Qt.Key_Left]: [-1, 0], [Qt.Key_L]: [1, 0], [Qt.Key_Right]: [1, 0], [Qt.Key_K]: [0, -1], [Qt.Key_Up]: [0, -1], [Qt.Key_J]: [0, 1], [Qt.Key_Down]: [0, 1] }[event.key];
            if (Screenshot.phase === "capture") {
                return;
            } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
                Screenshot.cancel();
            } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.text === "+" || event.text === "=") {
                Screenshot.step_zoom(1);
            } else if (event.key === Qt.Key_Minus || event.text === "-") {
                Screenshot.step_zoom(-1);
            } else if (event.key === Qt.Key_M && !shift) {
                Screenshot.lens_on = !Screenshot.lens_on;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (toolbar) root.run_tool(Screenshot.tool_index);
                else {
                    if (!Screenshot.has_selection) Screenshot.select_screen(root.screen_name);
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
                if (shift) Screenshot.nudge(0, 0, dir[0] * step, dir[1] * step);
                else Screenshot.nudge(dir[0] * step, dir[1] * step, 0, 0);
            } else {
                return;
            }
            event.accepted = true;
        }
    }
}
