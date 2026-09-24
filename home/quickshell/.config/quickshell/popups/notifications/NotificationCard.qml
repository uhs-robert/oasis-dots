// home/quickshell/.config/quickshell/popups/notifications/NotificationCard.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import "../../theme"
import "../../services"

// A single notification row, shared by the All/Apps/Critical tabs. Every Text below sets
// Layout.minimumWidth: 0 so a long unbroken summary/body can never grow the card past its width.
Item {
    id: root

    property var entry: null
    property bool selected: false

    signal invoke_requested()
    signal select_requested()

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

    function relative_time(ms) {
        const diff_s = Math.max(0, Math.floor((Date.now() - ms) / 1000));
        if (diff_s < 60) return "now";
        if (diff_s < 3600) return Math.floor(diff_s / 60) + "m";
        if (diff_s < 86400) return Math.floor(diff_s / 3600) + "h";
        const d = new Date(ms);
        const now = new Date();
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "HH:mm");
        if (Date.now() - ms < 7 * 86400000) return Qt.formatDate(d, "ddd");
        return Qt.formatDate(d, "MMM d");
    }

    implicitHeight: card.implicitHeight
    height: implicitHeight
    clip: true

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: layout.implicitHeight + 20
        radius: Style.radius(8)
        color: Style.boxed_cards ? (root.selected ? Qt.alpha(Style.caret_color, 0.08) : "transparent") : root.selected ? Theme.bg_surface : Theme.bg_mantle
        border.width: 1
        border.color: !Style.boxed_cards ? Theme.ui_border : root.selected ? Style.caret_color : Qt.alpha(root.accent, 0.6)
        clip: true

        Text {
            visible: Style.boxed_cards && root.selected && Style.row_cursor !== "" && Style.caret_phase
            x: 4
            y: layout.y + 1
            text: Style.row_cursor
            color: Style.caret_color
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 1
            font.bold: true
        }

        Rectangle {
            visible: !Style.boxed_cards
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 4
            radius: Style.radius(2)
            color: root.accent
        }

        Rectangle {
            visible: root.entry && !root.entry.read
            width: 8
            height: 8
            radius: Style.radius(4)
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            color: Theme.theme_primary
        }

        RowLayout {
            id: layout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            anchors.leftMargin: 16
            spacing: 10

            Image {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                visible: root.notification && (root.notification.image !== "" || root.notification.appIcon !== "")
                source: root.notification ? (root.notification.image !== "" ? root.notification.image : Quickshell.iconPath(root.notification.appIcon, true)) : ""
                fillMode: Image.PreserveAspectFit
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: Style.boxed_cards
                        ? "[" + (root.notification ? root.notification.appName : "") + "] " + (root.entry ? root.relative_time(root.entry.time) : "") + root.urgency_tag
                        : (root.notification ? root.notification.appName : "") + "  ·  " + (root.entry ? root.relative_time(root.entry.time) : "")
                    color: Style.boxed_cards ? root.accent : Theme.fg_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - (Style.boxed_cards ? 3 : 1)
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
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    visible: root.notification && root.notification.body !== ""
                    maximumLineCount: 3
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

                            implicitWidth: Math.min(action_label.implicitWidth + 18, layout.width)
                            implicitHeight: 26
                            radius: Style.radius(13)
                            color: Style.boxed_cards ? "transparent" : Theme.bg_surface
                            border.width: Style.boxed_cards ? 1 : 0
                            border.color: Style.key_border

                            Text {
                                id: action_label
                                anchors.centerIn: parent
                                anchors.margins: 4
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, layout.width - 18)
                                horizontalAlignment: Text.AlignHCenter
                                text: action_chip.modelData.text
                                color: Theme.theme_secondary
                                font.family: Style.font_family
                                font.pixelSize: Style.font_size - 3
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.select_requested();
                                    NotificationState.invoke_action(root.entry, action_chip.modelData);
                                }
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: {
                root.select_requested();
                root.invoke_requested();
            }
        }
    }
}
