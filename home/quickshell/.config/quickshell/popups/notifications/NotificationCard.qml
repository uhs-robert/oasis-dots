// home/quickshell/.config/quickshell/popups/notifications/NotificationCard.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import "../../components"
import "../../theme"
import "../../services"

// A single notification row, shared by the All/Apps/Critical tabs. Every Text below sets
// Layout.minimumWidth: 0 so a long unbroken summary/body can never grow the card past its width.
Item {
    id: root

    property var entry: null
    property bool selected: false
    property int focused_action: -1
    // The card's 1-based position in the list, shown by styles with channel cards.
    property int channel: 0
    readonly property bool channels: Style.card_layout === "channel"
    readonly property bool critical: !!root.notification && root.notification.urgency === NotificationUrgency.Critical

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
        color: Style.card_layout !== "" ? "transparent" : Style.boxed_cards ? (root.selected ? Qt.alpha(Style.caret_color, 0.08) : "transparent") : root.selected ? Theme.bg_surface : Theme.bg_mantle
        border.width: Style.card_layout !== "" ? 0 : 1
        border.color: !Style.boxed_cards ? Theme.ui_border : root.selected && Style.selection_brackets.a <= 0 ? Style.caret_color : Qt.alpha(root.accent, 0.6)
        clip: true

        LockBrackets {
            shown: root.selected
        }

        CardRule {
            visible: Style.card_layout === "rule"
            selected: root.selected
        }

        PixelBox {
            visible: Style.card_layout === "pixel"
            anchors.fill: parent
            fill: Style.shade_0
            rings: [root.selected ? Style.shade_3 : Style.shade_2, Style.shade_0, Style.shade_3]
        }

        Loader {
            active: root.channels
            anchors.fill: parent
            z: -1
            sourceComponent: Item {
                CutBox {
                    anchors.fill: parent
                    cut_tr: 10
                    fill: root.selected ? Qt.alpha(Style.caret_color, 0.1) : Style.row_rule
                    fill_end: "transparent"
                    stroke: root.selected ? Style.selection_rule : Style.row_rule
                }

                CornerTick {
                    size: 10
                    color: root.selected ? Style.selection_rule : Style.corner_tick
                }

                Rectangle {
                    x: 47
                    width: 1
                    height: parent.height
                    color: root.selected ? Style.selection_rule : Style.frame_line
                }

                Rectangle {
                    visible: root.selected
                    width: 3
                    height: parent.height
                    color: Style.caret_color
                }

                Column {
                    x: 0
                    y: 8
                    width: 48
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "CH-" + String(root.channel).padStart(2, "0")
                        color: root.selected ? Style.caret_color : Style.text_primary
                        font.family: Style.mono_font
                        font.pixelSize: Style.font_size - 3
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "T-" + (root.entry ? root.relative_time(root.entry.time).toUpperCase() : "")
                        color: Style.text_muted
                        font.family: Style.mono_font
                        font.pixelSize: Style.font_size - 5
                    }

                    Hazard {
                        visible: root.critical
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 28
                        height: 5
                        stripe: Theme.theme_label
                        tile: 6
                        line: 2
                    }
                }
            }
        }

        Text {
            visible: Style.boxed_cards && root.selected && Style.row_cursor !== "" && Style.caret_phase && Style.card_layout !== "pixel"
            x: 4
            y: layout.y + 1
            text: Style.row_cursor
            color: Style.caret_color
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 1
            font.bold: true
        }

        Rectangle {
            visible: Style.boxed_cards && Style.card_edge.a > 0
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 2
            color: Style.card_edge
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
            anchors.leftMargin: root.channels ? 58 : 16
            spacing: 10

            Image {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: root.width < 320 ? 32 : 44
                Layout.preferredHeight: Layout.preferredWidth
                visible: !root.channels && root.notification && (root.notification.image !== "" || root.notification.appIcon !== "")
                source: root.notification ? (root.notification.image !== "" ? root.notification.image : Quickshell.iconPath(root.notification.appIcon, true)) : ""
                fillMode: Image.PreserveAspectFit
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 3

                RowLabel {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    rightPadding: root.channels ? priority_text.implicitWidth + 8 : 0
                    label: root.channels ? (root.notification ? root.notification.appName : "") : Style.boxed_cards
                        ? "[" + (root.notification ? root.notification.appName : "") + "] " + (root.entry ? root.relative_time(root.entry.time) : "") + root.urgency_tag
                        : (root.notification ? root.notification.appName : "") + "  ·  " + (root.entry ? root.relative_time(root.entry.time) : "")
                    color: root.channels ? Style.text_muted : Style.boxed_cards ? root.accent : Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - (Style.boxed_cards ? 3 : 1)
                    font.bold: root.channels
                    font.capitalization: root.channels ? Font.AllUppercase : Font.MixedCase
                    font.letterSpacing: root.channels ? Style.label_spacing : 0

                    Text {
                        id: priority_text
                        visible: root.channels
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "PRI " + (root.critical ? "CRITICAL" : root.notification && root.notification.urgency === NotificationUrgency.Low ? "LOW" : "NORMAL")
                        color: root.critical ? Theme.theme_label : Style.text_muted
                        font.family: Style.mono_font
                        font.pixelSize: Style.font_size - 4
                    }
                }

                RowLabel {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    label: root.notification ? root.notification.summary : ""
                    color: Theme.fg_core
                    font.bold: Style.title_font_family === Style.font_family
                    font.family: Style.title_font_family
                    font.pixelSize: Style.font_size + (Style.boxed_cards ? 0 : 1)
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    visible: root.notification && NotificationState.clean_body(root.notification.body) !== ""
                    maximumLineCount: 3
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

                            implicitWidth: Math.min(action_label.implicitWidth + 18 + (action_chip.hand ? 20 : 0), layout.width)
                            implicitHeight: 26
                            radius: Style.pill_chips ? height / 2 : Style.radius(13)
                            color: action_chip.hand ? "transparent" : action_chip.focused ? Style.chip_pick : Style.boxed_cards ? "transparent" : Theme.bg_surface
                            border.width: Style.boxed_cards || action_chip.focused ? 1 : 0
                            border.color: action_chip.focused ? Style.chip_pick : Style.chip_border.a > 0 ? Style.chip_border : Style.key_border

                            Text {
                                id: action_label
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: action_chip.hand ? 10 : 0
                                anchors.margins: 4
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, layout.width - 18)
                                horizontalAlignment: Text.AlignHCenter
                                text: action_chip.modelData.text
                                color: action_chip.hand ? Theme.fg_strong : action_chip.focused ? Theme.bg_crust : Theme.theme_secondary
                                font.bold: action_chip.focused
                                font.family: Style.label_font_family
                                font.pixelSize: Style.font_size - 3
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
