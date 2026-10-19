pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.ui.menu
import qs.ui.keys

// One per screen while voxcmd's click offers several matches: outlines each candidate's box with a numbered keycap,
// picked by number key, click or a spoken number. Only the screen with the first box takes the keyboard.
PanelWindow {
    id: root

    required property var modelData
    readonly property string screen_name: root.modelData.name
    readonly property bool keyboard_owner: ClickHints.focus_screen === root.screen_name
    property bool help_open: false
    readonly property string help_text: "1-9 pick that box · 0 box 10 · Esc/q cancel"
    readonly property real keycap_gap: 3
    readonly property bool skinned_cursor: cursor_loader.status === Loader.Ready
    property point mouse_point: Qt.point(0, 0)

    screen: root.modelData
    visible: true
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "quickshell-click-hints"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive would make Hyprland send every screen's pointer input to this one surface.
    WlrLayershell.keyboardFocus: root.keyboard_owner ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function set_help(open) {
        root.help_open = open;
        Qt.callLater(() => open ? key_help.forceActiveFocus() : keys_item.forceActiveFocus());
    }

    // The smallest box under the point, so a box nested in another stays pickable.
    function box_at(x, y) {
        let best = -1;
        let best_area = Infinity;
        ClickHints.choices.forEach((c, i) => {
            const lx = c.x - root.modelData.x;
            const ly = c.y - root.modelData.y;
            if (x >= lx && x < lx + c.w && y >= ly && y < ly + c.h && c.w * c.h < best_area) {
                best = i;
                best_area = c.w * c.h;
            }
        });
        return best;
    }

    // A faint veil shows the screen is modal and lifts the outlines off busy content.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.18
    }

    MouseArea {
        id: pointer_area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.skinned_cursor ? Qt.BlankCursor : Qt.ArrowCursor
        onPositionChanged: mouse => root.mouse_point = Qt.point(mouse.x, mouse.y)
        onClicked: mouse => {
            const i = root.box_at(mouse.x, mouse.y);
            ClickHints.answer(i + 1);
        }
    }

    Repeater {
        model: ClickHints.choices

        delegate: Item {
            id: hint

            required property var modelData
            required property int index
            readonly property real box_x: hint.modelData.x - root.modelData.x
            readonly property real box_y: hint.modelData.y - root.modelData.y
            readonly property bool on_screen: hint.box_x + hint.modelData.w > 0 && hint.box_x < root.width && hint.box_y + hint.modelData.h > 0 && hint.box_y < root.height

            visible: hint.on_screen
            x: hint.box_x
            y: hint.box_y
            width: hint.modelData.w
            height: hint.modelData.h

            // A dark rim under the accent line keeps the outline visible on light and dark content alike.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                color: "transparent"
                radius: Style.radius(3)
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.55)
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                color: Qt.rgba(Style.accent_color.r, Style.accent_color.g, Style.accent_color.b, 0.12)
                radius: Style.radius(3)
                border.width: 2
                border.color: Style.accent_color
            }

            // A style whose keycaps have no fill (neovim) would leave a bare digit over the page, so it gets a plate.
            Rectangle {
                id: plate
                readonly property bool bare: keycap.st.key_bg.a === 0
                // Above the box so the text stays readable; below it when the box touches the top edge.
                readonly property bool fits_above: hint.box_y - height - root.keycap_gap >= 0
                // Keeps the cap on screen when the box starts left of it.
                x: Math.max(0, -hint.x)
                y: plate.fits_above ? -height - root.keycap_gap : hint.height + root.keycap_gap
                width: keycap.width + (plate.bare ? 6 : 0)
                height: keycap.height + (plate.bare ? 4 : 0)
                radius: Style.radius(3)
                color: plate.bare ? Style.frame_color : "transparent"
                border.width: plate.bare ? 1 : 0
                border.color: Style.accent_color

                KeyBadge {
                    id: keycap
                    anchors.centerIn: parent
                    key: String(hint.index + 1)
                    font_px: Style.fs(2)
                }
            }
        }
    }

    // The skin's cursor above the outlines, as RegionSelector and ZoomReticle load it.
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
                at: Qt.binding(() => root.mouse_point),
                shown: Qt.binding(() => pointer_area.containsMouse),
                screen_name: Qt.binding(() => root.screen_name),
                origin: Qt.binding(() => Qt.point(root.modelData.x, root.modelData.y)),
                target_mode: false
            };
            if (cursor_loader.skin === "scope") {
                props.box_w = 58;
                props.box_h = 38;
            }
            cursor_loader.setSource(Qt.resolvedUrl("../../ui/cursors/" + cursor_loader.skin.charAt(0).toUpperCase() + cursor_loader.skin.slice(1) + ".qml"), props);
        }
    }

    Rectangle {
        id: status_pill
        visible: root.keyboard_owner
        // Bottom left: the voxtype OSD takes the bottom center while the overlay listens.
        anchors.left: parent.left
        anchors.leftMargin: 24
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        width: Math.min(parent.width - 32, pill.implicitWidth + 24)
        height: pill.implicitHeight + 12
        radius: Style.frame_radius
        color: Style.frame_color
        border.width: Style.frame_border_width
        border.color: Style.frame_border_color

        ColumnLayout {
            id: pill
            anchors.centerIn: parent
            spacing: 4

            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: ClickHints.label !== ""
                text: ClickHints.label
                textFormat: Text.PlainText
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: ClickHints.listening
                text: VoxtypeState.recording ? "󰍬 Listening" : "󰔟 Transcribing"
                textFormat: Text.PlainText
                color: VoxtypeState.recording ? Style.pal.label : Style.pal.warning
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
            }

            MenuFooter {
                id: footer_hint
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(implicitWidth, root.width - 56)
                wrap: false
                ruled: false
                text: "1-9, 0 pick · say a number · Esc cancel · ? help"
            }
        }
    }

    Rectangle {
        id: help_box
        visible: root.keyboard_owner && root.help_open
        z: 3
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, Style.px(520))
        height: Math.min(parent.height - 160, Style.px(200))
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
            text: Style.title_text("Click keys", Style)
            color: Style.text_strong
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

    Item {
        id: keys_item
        anchors.fill: parent
        focus: root.keyboard_owner
        Component.onCompleted: if (root.keyboard_owner) keys_item.forceActiveFocus()

        Keys.onPressed: event => {
            const digit = event.key - Qt.Key_0;
            const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
            if (event.key === Qt.Key_Question || event.text === "?") {
                root.set_help(true);
            } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
                ClickHints.answer(0);
            } else if (plain && digit >= 0 && digit <= 9) {
                const number = digit === 0 ? 10 : digit;
                if (number <= ClickHints.choices.length) ClickHints.answer(number);
            } else {
                return;
            }
            event.accepted = true;
        }
    }
}
