// home/quickshell/.config/quickshell/components/NotificationToastCard.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import "../theme"
import "../services"

Rectangle {
    id: root

    property var entry: null
    property bool selected: false
    property int focused_action: -1
    readonly property var notification: root.entry ? root.entry.notification : null

    readonly property var actions: {
        if (!root.notification || !root.notification.actions) return [];
        const list = [];
        for (let i = 0; i < root.notification.actions.length; i++) {
            if (root.notification.actions[i].identifier !== "default") list.push(root.notification.actions[i]);
        }
        return list;
    }

    readonly property color accent: {
        if (!root.notification) return Style.text_dim;
        if (root.notification.urgency === NotificationUrgency.Critical) return Theme.error;
        if (root.notification.urgency === NotificationUrgency.Low) return Style.text_dim;
        return Style.text_primary;
    }

    readonly property string urgency_tag: {
        if (!root.notification) return "";
        if (root.notification.urgency === NotificationUrgency.Critical) return " !! critical";
        if (root.notification.urgency === NotificationUrgency.Low) return " · low";
        return "";
    }

    readonly property int text_style: Style.glow ? Text.Outline : Style.text_shadow.a > 0 ? Text.Raised : Text.Normal
    readonly property color glow_color: Style.glow ? Qt.alpha(Theme.theme_primary, 0.3) : Style.text_shadow

    property int time_tick: 0
    readonly property string relative_time: {
        void root.time_tick;
        if (!root.entry) return "";
        const s = Math.max(0, Math.floor((Date.now() - root.entry.time) / 1000));
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + "m";
        return Math.floor(s / 3600) + "h";
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.time_tick += 1
    }

    implicitHeight: layout.implicitHeight + 16 + Style.inset_pad * 2
    radius: Style.radius(8)
    color: Style.frame_visor || Style.custom_frame ? "transparent" : Style.boxed_cards
        ? (root.selected ? Qt.tint(Style.frame_color, Qt.alpha(Style.caret_color, 0.08)) : Style.frame_color)
        : (root.selected ? Theme.bg_surface : Theme.bg_mantle)
    border.width: Style.frame_visor || Style.custom_frame ? 0 : root.selected && !Style.boxed_cards ? 2 : 1
    border.color: root.selected ? Style.caret_color : Style.boxed_cards ? root.accent : Theme.ui_border
    clip: true

    opacity: 0
    Component.onCompleted: enter_anim.start()

    NumberAnimation {
        id: enter_anim
        target: root
        property: "opacity"
        from: 0
        to: 1
        duration: 180
        easing.type: Easing.OutCubic
    }

    // Closes with a short fade, then tells the state to actually drop the entry.
    function close_animated(action) {
        exit_anim.action = action;
        exit_anim.start();
    }

    NumberAnimation {
        id: exit_anim
        property string action: "hide"
        target: root
        property: "opacity"
        to: 0
        duration: 150
        easing.type: Easing.InCubic
        onFinished: {
            if (!root.entry) return;
            if (exit_anim.action === "dismiss") NotificationState.dismiss(root.entry);
            else if (exit_anim.action === "default") NotificationState.invoke_default(root.entry);
            else NotificationState.hide_toast(root.entry);
        }
    }

    VisorGlass {
        anchors.fill: parent
        border_color: root.selected ? Style.caret_color : Qt.alpha(root.accent, 0.5)
    }

    FrameShade {
        visible: Style.boxed_cards && Style.frame_shade.a > 0 && !Style.custom_frame
        anchors.fill: parent
        anchors.margins: root.border.width
        top_radius: Math.max(0, root.radius - root.border.width)
        bottom_radius: top_radius
    }

    CustomFrame {
        anchors.fill: parent
        chamfer_edge: root.selected ? Style.caret_color : Style.frame_border_color
        octagon_edge: root.selected ? Style.caret_color : root.accent
        octagon_cut: Math.min(Style.frame_octagon, 10)
        struts: false
    }

    LockBrackets {
        anchors.margins: 3
        shown: root.selected
    }

    FrameInset {
        visible: Style.boxed_cards && Style.frame_inset_width > 0
        edge: root.border.width
        top_radius: root.radius
        bottom_radius: root.radius
    }

    Rectangle {
        visible: !Style.boxed_cards
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 3
        radius: 1.5
        color: root.accent
    }

    Rectangle {
        visible: Style.frame_top_rule
        x: root.border.width
        y: root.border.width
        width: root.width - root.border.width * 2
        height: Style.accent_height
        color: root.accent
    }

    DashedOutline {
        visible: root.selected && Style.boxed_cards && Style.selection_outline.a > 0
        anchors.fill: parent
        anchors.margins: 3
        color: Style.selection_outline
    }

    Rectangle {
        visible: Style.card_edge.a > 0 && !(root.selected && Style.selection_bar)
        x: 1
        y: 1
        width: 2
        height: root.height - 2
        color: Style.card_edge
    }

    Rectangle {
        visible: root.selected && Style.selection_bar && !Style.frame_visor
        x: 1 + (Style.frame_cut > 0 ? Style.inset_pad : 0)
        y: x
        width: 2
        height: root.height - y * 2
        color: Style.caret_color
    }

    Text {
        visible: root.selected && Style.row_cursor !== "" && Style.caret_phase
        x: 3 + Style.inset_pad
        y: layout.y + 1
        text: Style.row_cursor
        color: Style.caret_color
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 3
        font.bold: true
    }

    // Static scanlines; nothing animates them.
    Repeater {
        model: Style.scanlines && Style.frame_octagon <= 0 ? Math.ceil(root.height / 3) : 0

        Rectangle {
            required property int index
            y: index * 3
            width: root.width
            height: 1
            color: Qt.alpha(Theme.theme_primary, 0.05)
        }
    }

    Dither {
        visible: Style.boxed_cards && Style.dither.a > 0
        anchors.fill: parent
        anchors.margins: root.border.width
        color: Style.dither
        radius: root.radius
        top_radius: root.radius
    }

    // Styles with a title strip head the toast like a window: the app line sits on the strip.
    Rectangle {
        visible: Style.title_strip.a > 0
        x: root.border.width
        y: root.border.width
        width: root.width - root.border.width * 2
        height: layout.y + header_row.height + 4 - y
        color: Style.title_strip

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Style.hairline.a > 0 ? Style.hairline : Style.frame_border_color
        }
    }

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8 + Style.inset_pad
        anchors.leftMargin: (Style.row_cursor !== "" ? 16 : 12) + Style.inset_pad
        spacing: 8

        Image {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            visible: root.notification && (root.notification.image !== "" || root.notification.appIcon !== "")
            source: root.notification ? (root.notification.image !== "" ? root.notification.image : Quickshell.iconPath(root.notification.appIcon, true)) : ""
            fillMode: Image.PreserveAspectFit
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2

            RowLayout {
                id: header_row
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.bottomMargin: Style.title_strip.a > 0 ? 6 : 0
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: Style.boxed_cards
                        ? "[" + (root.notification ? root.notification.appName : "") + "] " + root.relative_time + root.urgency_tag
                        : (root.notification ? root.notification.appName : "") + "  ·  " + root.relative_time
                    color: Style.boxed_cards ? root.accent : Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - (Style.boxed_cards ? 3 : 4)
                    style: root.text_style
                    styleColor: root.glow_color
                }

                Text {
                    text: "×"
                    color: Style.text_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size + 2

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        onClicked: root.close_animated("dismiss")
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.notification ? root.notification.summary : ""
                color: Theme.fg_core
                font.bold: Style.title_font_family === Style.font_family
                font.family: Style.title_font_family
                font.pixelSize: Style.font_size + (Style.boxed_cards ? 0 : 1)
                style: root.text_style
                styleColor: root.glow_color
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: root.notification && NotificationState.clean_body(root.notification.body) !== ""
                maximumLineCount: 4
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                // StyledText (unlike RichText) elides correctly and still renders <b>/<i>/etc.
                textFormat: Text.StyledText
                text: root.notification ? NotificationState.clean_body(root.notification.body) : ""
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.font_size
            }

            Flow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 2
                visible: root.actions.length > 0
                spacing: 6

                Repeater {
                    model: root.actions

                    Rectangle {
                        id: action_chip
                        required property var modelData
                        required property int index
                        readonly property bool focused: action_chip.index === root.focused_action
                        readonly property bool hand: action_chip.focused && Style.hand_cursor

                        implicitWidth: Math.min(action_label.implicitWidth + 16 + (action_chip.hand ? 20 : 0), layout.width)
                        implicitHeight: 22
                        radius: Style.pill_chips ? height / 2 : Style.radius(11)
                        color: action_chip.hand ? "transparent" : action_chip.focused ? Style.chip_pick : Style.boxed_cards ? "transparent" : Theme.bg_surface
                        border.width: Style.boxed_cards || action_chip.focused ? 1 : 0
                        border.color: action_chip.focused ? Style.chip_pick : Style.chip_border.a > 0 ? Style.chip_border : Style.key_border

                        Text {
                            id: action_label
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: action_chip.hand ? 10 : 0
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, layout.width - 16)
                            horizontalAlignment: Text.AlignHCenter
                            text: action_chip.modelData.text
                            color: action_chip.hand ? Theme.fg_strong : action_chip.focused ? Theme.bg_crust : Theme.theme_secondary
                            font.bold: action_chip.focused
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - (Style.boxed_cards ? 3 : 4)
                            style: action_chip.focused ? Text.Normal : root.text_style
                            styleColor: root.glow_color
                        }

                        HandCursor {
                            visible: action_chip.hand
                            anchors.right: action_label.left
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            height: 10
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                NotificationState.invoke_action(root.entry, action_chip.modelData);
                            }
                        }
                    }
                }
            }
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (!root.entry) return;
            if (hovered) NotificationState.pause_toast(root.entry);
            else NotificationState.resume_toast(root.entry);
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: {
            const has_default = NotificationState.find_default_action(root.notification) !== null;
            root.close_animated(has_default ? "default" : "hide");
        }
    }
}
