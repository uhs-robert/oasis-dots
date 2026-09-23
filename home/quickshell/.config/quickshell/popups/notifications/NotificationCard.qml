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
        radius: 8
        color: root.selected ? Theme.bg_surface : Theme.bg_mantle
        border.width: 1
        border.color: Theme.ui_border
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 4
            radius: 2
            color: root.accent
        }

        Rectangle {
            visible: root.entry && !root.entry.read
            width: 8
            height: 8
            radius: 4
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
                    text: (root.notification ? root.notification.appName : "") + "  ·  " + (root.entry ? root.relative_time(root.entry.time) : "")
                    color: Theme.fg_muted
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size - 1
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.notification ? root.notification.summary : ""
                    color: Theme.fg_core
                    font.bold: true
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size + 1
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
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size
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
                            radius: 13
                            color: Theme.bg_surface

                            Text {
                                id: action_label
                                anchors.centerIn: parent
                                anchors.margins: 4
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, layout.width - 18)
                                horizontalAlignment: Text.AlignHCenter
                                text: action_chip.modelData.text
                                color: Theme.theme_secondary
                                font.family: Theme.font_family
                                font.pixelSize: Theme.popup_font_size - 3
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
