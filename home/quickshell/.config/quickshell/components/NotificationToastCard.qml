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
        if (!root.notification) return Theme.fg_dim;
        if (root.notification.urgency === NotificationUrgency.Critical) return Theme.error;
        if (root.notification.urgency === NotificationUrgency.Low) return Theme.fg_dim;
        return Theme.theme_primary;
    }

    readonly property string urgency_tag: {
        if (!root.notification) return "";
        if (root.notification.urgency === NotificationUrgency.Critical) return " !! critical";
        if (root.notification.urgency === NotificationUrgency.Low) return " · low";
        return "";
    }

    readonly property int text_style: Style.glow ? Text.Outline : Text.Normal
    readonly property color glow_color: Qt.alpha(Theme.theme_primary, 0.3)

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

    implicitHeight: layout.implicitHeight + 16
    radius: Style.radius(8)
    color: Style.boxed_cards
        ? (root.selected ? Qt.tint(Style.frame_color, Qt.alpha(Style.caret_color, 0.08)) : Style.frame_color)
        : (root.selected ? Theme.bg_surface : Theme.bg_mantle)
    border.width: root.selected && !Style.boxed_cards ? 2 : 1
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

    Rectangle {
        visible: !Style.boxed_cards
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 3
        radius: 1.5
        color: root.accent
    }

    DashedOutline {
        visible: root.selected && Style.boxed_cards && Style.selection_outline.a > 0
        anchors.fill: parent
        anchors.margins: 3
        color: Style.selection_outline
    }

    Rectangle {
        visible: root.selected && Style.selection_bar
        x: 1
        y: 1
        width: 2
        height: root.height - 2
        color: Style.caret_color
    }

    Text {
        visible: root.selected && Style.row_cursor !== "" && Style.caret_phase
        x: 3
        y: layout.y + 1
        text: Style.row_cursor
        color: Style.caret_color
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 3
        font.bold: true
    }

    // Static scanlines; nothing animates them.
    Repeater {
        model: Style.scanlines ? Math.ceil(root.height / 3) : 0

        Rectangle {
            required property int index
            y: index * 3
            width: root.width
            height: 1
            color: Qt.alpha(Theme.theme_primary, 0.05)
        }
    }

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        anchors.leftMargin: Style.row_cursor !== "" ? 16 : 12
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
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: Style.boxed_cards
                        ? "[" + (root.notification ? root.notification.appName : "") + "] " + root.relative_time + root.urgency_tag
                        : (root.notification ? root.notification.appName : "") + "  ·  " + root.relative_time
                    color: Style.boxed_cards ? root.accent : Theme.fg_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - (Style.boxed_cards ? 3 : 4)
                    style: root.text_style
                    styleColor: root.glow_color
                }

                Text {
                    text: "×"
                    color: Theme.fg_dim
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
                font.bold: true
                font.family: Style.font_family
                font.pixelSize: Style.font_size + (Style.boxed_cards ? 0 : 1)
                style: root.text_style
                styleColor: root.glow_color
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: root.notification && root.notification.body !== ""
                maximumLineCount: 4
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                // StyledText (unlike RichText) elides correctly and still renders <b>/<i>/etc.
                textFormat: Text.StyledText
                text: root.notification ? root.notification.body : ""
                color: Theme.fg_muted
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

                        implicitWidth: Math.min(action_label.implicitWidth + 16, layout.width)
                        implicitHeight: 22
                        radius: Style.radius(11)
                        color: action_chip.focused ? Theme.theme_secondary : Style.boxed_cards ? "transparent" : Theme.bg_surface
                        border.width: Style.boxed_cards || action_chip.focused ? 1 : 0
                        border.color: action_chip.focused ? Theme.theme_secondary : Style.key_border

                        Text {
                            id: action_label
                            anchors.centerIn: parent
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, layout.width - 16)
                            horizontalAlignment: Text.AlignHCenter
                            text: action_chip.modelData.text
                            color: action_chip.focused ? Theme.bg_crust : Theme.theme_secondary
                            font.bold: action_chip.focused
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - (Style.boxed_cards ? 3 : 4)
                            style: action_chip.focused ? Text.Normal : root.text_style
                            styleColor: root.glow_color
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
