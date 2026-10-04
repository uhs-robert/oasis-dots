// home/quickshell/.config/quickshell/components/ZoomReticle.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

// One per screen while zoom is on: owns keyboard and pointer, and draws the skin's reticle with the loupe's sampled area cut out.
PanelWindow {
    id: root

    required property var modelData
    readonly property string screen_name: root.modelData.name
    readonly property bool keyboard_owner: Zoom.focus_screen === root.screen_name
    readonly property bool mine: Zoom.reticle_shown && Zoom.cursor_screen === root.screen_name
    property bool help_open: false
    property point last_mouse: Qt.point(-1, -1)
    readonly property string help_text: "hjkl move 10px · H/J/K/L move 100px · C-hjkl move 1px · C-H/J/K/L move 300px · i/o or +/- or wheel zoom · [/] loupe size · m loupe · f full screen · Esc/q exit"
    readonly property real margin: 2
    readonly property real hole_half: Math.ceil(Zoom.sample_half) + root.margin

    screen: root.modelData
    visible: true
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "quickshell-zoom-reticle"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive would make Hyprland send every screen's pointer input to this one surface.
    WlrLayershell.keyboardFocus: root.keyboard_owner ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function set_help(open) {
        root.help_open = open;
        Qt.callLater(() => open ? key_help.forceActiveFocus() : keys_item.forceActiveFocus());
    }


    Binding {
        target: Zoom
        property: "scan_step"
        value: cursor_loader.item?.scan_step ?? -1
        when: root.mine
    }

    Item {
        id: hole_mask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            visible: Zoom.lens_on
            x: Math.floor(Zoom.cursor_point.x) - root.hole_half
            y: Math.floor(Zoom.cursor_point.y) - root.hole_half
            width: root.hole_half * 2 + 1
            height: width
            color: "black"
        }
    }

    Item {
        anchors.fill: parent
        visible: root.mine
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: hole_mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
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
                    at: Qt.binding(() => Zoom.cursor_point),
                    shown: true,
                    screen_name: Qt.binding(() => root.screen_name),
                    origin: Qt.binding(() => Qt.point(root.modelData.x, root.modelData.y)),
                    target_mode: false
                };
                if (cursor_loader.skin === "scope") {
                    props.box_w = Qt.binding(() => root.hole_half * 2 + 5);
                    props.box_h = Qt.binding(() => root.hole_half * 2 + 5);
                }
                cursor_loader.setSource(Qt.resolvedUrl("picker/cursors/" + cursor_loader.skin.charAt(0).toUpperCase() + cursor_loader.skin.slice(1) + ".qml"), props);
            }
        }
    }

    Rectangle {
        id: help_box
        visible: root.keyboard_owner && root.help_open
        z: 3
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, Style.px(520))
        height: Math.min(parent.height - 160, Style.px(300))
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
            text: Style.title_text("Zoom keys", Style)
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
            text: "hjkl move · i/o zoom · [/] loupe size · m loupe · f full screen · Esc exit · ? help"
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        cursorShape: Zoom.full ? Qt.ArrowCursor : Qt.BlankCursor
        onWheel: wheel => Zoom.step(wheel.angleDelta.y > 0 ? 1 : wheel.angleDelta.y < 0 ? -1 : 0)
        onPositionChanged: mouse => {
            if (mouse.x === root.last_mouse.x && mouse.y === root.last_mouse.y) return;
            root.last_mouse = Qt.point(mouse.x, mouse.y);
            if (Date.now() - Zoom.warp_at < 120) return;
            Zoom.place(root.modelData.x + mouse.x, root.modelData.y + mouse.y);
        }
    }

    Item {
        id: keys_item
        anchors.fill: parent
        focus: root.keyboard_owner
        Component.onCompleted: if (root.keyboard_owner) keys_item.forceActiveFocus()

        property var held: ({})

        Keys.onReleased: event => {
            if (!event.isAutoRepeat) delete keys_item.held[event.key];
        }

        Keys.onPressed: event => {
            const shift = event.modifiers & Qt.ShiftModifier;
            const ctrl = event.modifiers & Qt.ControlModifier;
            const step = ctrl && shift ? 300 : shift ? 100 : ctrl ? 1 : 10;
            const dir = { [Qt.Key_H]: [-1, 0], [Qt.Key_Left]: [-1, 0], [Qt.Key_L]: [1, 0], [Qt.Key_Right]: [1, 0], [Qt.Key_K]: [0, -1], [Qt.Key_Up]: [0, -1], [Qt.Key_J]: [0, 1], [Qt.Key_Down]: [0, 1] }[event.key];
            if (event.key === Qt.Key_Question || event.text === "?") {
                root.set_help(true);
            } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
                Zoom.stop();
            } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.text === "+" || event.text === "=" || (!shift && event.key === Qt.Key_I)) {
                Zoom.step(1);
            } else if (event.key === Qt.Key_Minus || event.text === "-" || (!shift && event.key === Qt.Key_O)) {
                Zoom.step(-1);
            } else if (event.key === Qt.Key_BracketLeft || event.text === "[") {
                Zoom.size(-1);
            } else if (event.key === Qt.Key_BracketRight || event.text === "]") {
                Zoom.size(1);
            } else if (event.key === Qt.Key_M && !shift) {
                Zoom.lens_on = !Zoom.lens_on;
            } else if (event.key === Qt.Key_F && !shift) {
                if (!event.isAutoRepeat) Zoom.toggle_full();
            } else if (dir) {
                keys_item.held[event.key] = dir;
                let dx = 0;
                let dy = 0;
                for (const k in keys_item.held) {
                    dx += keys_item.held[k][0];
                    dy += keys_item.held[k][1];
                }
                Zoom.move(Math.sign(dx) * step, Math.sign(dy) * step);
            } else {
                return;
            }
            event.accepted = true;
        }
    }
}
