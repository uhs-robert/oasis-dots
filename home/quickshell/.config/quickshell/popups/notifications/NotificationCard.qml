// home/quickshell/.config/quickshell/popups/notifications/NotificationCard.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import "../../components"
import "../../theme"
import "../../services"
import "../weather" as Weather
import "../../components/snes" as Snes
import "../../components/ps1" as Ps1
import "../../components/ps2" as Ps2
import "../../components/oasis" as Oasis
import "../../components/modern" as Modern
import "../../components/neovim" as Neovim

// A single notification row, shared by the All/Apps/Critical tabs. Every Text below sets
// Layout.minimumWidth: 0 so a long unbroken summary/body can never grow the card past its width.
Item {
    id: root

    property var entry: null
    // Set by the list: entry.read changes in place, which a binding on entry can't see.
    property bool unread: false
    property bool selected: false
    property int focused_action: -1
    // Chrono Trigger dialogue boxes: the app speaks its summary and body in a blue window.
    readonly property bool dialogue: Style.card_layout === "dialogue"
    readonly property bool dq: Style.card_layout === "dq"
    // MGS codec calls: the app icon as the caller's portrait.
    readonly property bool codec: Style.console_views === "ps1"
    readonly property bool dialog: Style.card_layout === "dialog"
    // Layered cards with the app icon on a tinted tile.
    readonly property bool tile: Style.card_layout === "tile"
    readonly property bool notify: Style.card_layout === "notify"
    readonly property bool critical: !!root.notification && root.notification.urgency === NotificationUrgency.Critical

    readonly property bool focused_valid: root.focused_action >= 0 && root.focused_action < root.actions.length

    // What Enter does in the popup: the focused action, else the default.
    function enter() {
        if (!root.focused_valid) return root.invoke_requested();
        ThemeAudio.play("confirm");
        NotificationState.invoke_action(root.entry, root.actions[root.focused_action]);
        NotificationState.close_popup_if_empty();
    }

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
        if (root.notification.urgency === NotificationUrgency.Critical) return Style.pal.error;
        if (root.notification.urgency === NotificationUrgency.Low) return Style.text_dim;
        return root.notify ? Style.pal.info : Style.text_primary;
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
        if (d.toDateString() === now.toDateString()) return TimeFormat.format(d);
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
        implicitHeight: layout.implicitHeight + 20 + (({ dq: 8, dialogue: 3 })[Style.card_layout] || 0)
        radius: Style.radius(8)
        color: Style.card_layout !== "" ? "transparent" : Style.boxed_cards ? (root.selected ? Qt.alpha(Style.caret_color, 0.08) : "transparent") : root.selected ? Style.pal.bg_surface : Style.pal.bg_mantle
        border.width: Style.card_layout !== "" ? 0 : 1
        border.color: !Style.boxed_cards ? Style.pal.border : root.selected && Style.selection_brackets.a <= 0 ? Style.caret_color : Qt.alpha(root.accent, 0.6)
        clip: true

        LockBrackets {
            shown: root.selected
        }

        // Console windows behind the card, one per card_layout.
        Loader {
            anchors.fill: parent
            z: -1
            sourceComponent: ({ dq: dq_card, dialogue: dialogue_card, dialog: dialog_card, oasis: oasis_card, tile: tile_card, notify: notify_card })[Style.card_layout] || null
        }

        CardRule {
            visible: Style.card_layout === "rule"
            selected: root.selected
        }

        HandCursor {
            visible: root.dialogue && root.selected
            x: 5
            y: layout.y + 2
            width: 19
            height: 12
        }

        PixelBox {
            visible: Style.card_layout === "pixel"
            anchors.fill: parent
            fill: Style.shade_0
            rings: [root.selected ? Style.shade_3 : Style.shade_2, Style.shade_0, Style.shade_3]
        }

        Text {
            visible: Style.boxed_cards && root.selected && Style.row_cursor !== "" && Style.caret_phase && Style.card_layout !== "pixel" && !root.dialogue
            x: root.dq ? 9 : 4
            y: layout.y + 1
            text: Style.row_cursor
            color: Style.caret_color
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
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
            visible: !Style.boxed_cards && ["oasis", "tile"].indexOf(Style.card_layout) < 0
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 4
            radius: Style.radius(2)
            color: root.accent
        }

        Rectangle {
            visible: root.unread
            width: 8
            height: 8
            radius: Style.radius(4)
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            color: Style.pal.primary
        }

        RowLayout {
            id: layout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            anchors.leftMargin: root.dialogue ? 28 : root.dq ? 24 : root.tile ? 12 : 16
            anchors.rightMargin: root.dialogue ? 16 : 10
            spacing: 10

            Loader {
                active: root.codec
                visible: active
                Layout.alignment: Qt.AlignTop
                sourceComponent: Ps1.CodecPortrait {
                    notification: root.notification
                    size: root.width < 320 ? 34 : 44
                    ringing: !!root.entry && Date.now() - root.entry.time < 5000
                }
            }

            Loader {
                active: root.tile
                visible: active
                Layout.alignment: Qt.AlignTop
                sourceComponent: Modern.AccentTile {
                    size: root.width < 320 ? 32 : 36
                    tint: root.critical ? Style.pal.label : Style.pal.info
                    glyph: "\u{f0f3}"
                    notification: root.notification
                }
            }

            Image {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: root.width < 320 ? 32 : 44
                Layout.preferredHeight: Layout.preferredWidth
                visible: !root.codec && !root.tile && root.notification && (root.notification.image !== "" || root.notification.appIcon !== "")
                source: root.notification ? (root.notification.image !== "" ? root.notification.image : Quickshell.iconPath(root.notification.appIcon, true)) : ""
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectFit
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 3

                Loader {
                    active: root.notify
                    visible: active
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.rightMargin: root.unread ? 12 : 0
                    sourceComponent: Neovim.NotifyHeader {
                        app: root.notification ? root.notification.appName : ""
                        age: root.entry ? root.relative_time(root.entry.time) : ""
                        level: root.critical ? "critical" : root.urgency_tag === "" ? "" : "low"
                        accent: root.accent
                    }
                }

                RowLabel {
                    visible: !root.notify
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    label: root.dialogue ? (root.notification ? root.notification.appName : "") + ":" : root.dialog ? (root.notification ? root.notification.appName : "") + (root.dialog && root.entry ? "  ·  " + root.relative_time(root.entry.time) + root.urgency_tag : "") : Style.boxed_cards
                        ? "[" + (root.notification ? root.notification.appName : "") + "] " + (root.entry ? root.relative_time(root.entry.time) : "") + root.urgency_tag
                        : (root.notification ? root.notification.appName : "") + "  ·  " + (root.entry ? root.relative_time(root.entry.time) : "")
                    rightPadding: root.dialogue ? speaker_time.implicitWidth + 8 : 0
                    color: root.dialogue ? (root.critical ? Style.pal.label : Style.pal.secondary) : Style.boxed_cards ? root.accent : Style.text_muted
                    style: root.dialogue ? Text.Raised : Text.Normal
                    styleColor: Style.text_shadow
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size - (Style.boxed_cards ? 3 : 1)

                    Text {
                        id: speaker_time
                        visible: root.dialogue
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.entry ? root.relative_time(root.entry.time) + root.urgency_tag : ""
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-5)
                    }

                }

                RowLabel {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    Layout.leftMargin: root.dialogue ? 12 : 0
                    label: root.notification ? root.notification.summary : ""
                    color: root.dialogue ? Style.pal.fg_strong : Style.pal.fg
                    style: root.dialogue ? Text.Raised : Text.Normal
                    styleColor: Style.text_shadow
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
                    Layout.leftMargin: root.dialogue ? 12 : 0
                    text: root.notification ? NotificationState.clean_body(root.notification.body) : ""
                    lineHeight: root.dq ? 1.2 : 1
                    color: root.dialogue ? Style.pal.fg : Style.text_muted
                    style: root.dialogue ? Text.Raised : Text.Normal
                    styleColor: Style.text_shadow
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
                            color: action_chip.hand ? "transparent" : action_chip.focused ? Style.chip_pick : Style.boxed_cards ? "transparent" : root.tile ? Style.tab_active_bg : Style.pal.bg_surface
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
                                color: action_chip.hand ? Style.pal.fg_strong : action_chip.focused ? Style.pal.bg_crust : Style.chip_fg.a > 0 ? Style.chip_fg : Style.pal.secondary
                                font.bold: action_chip.focused
                                font.family: Style.label_font_family
                                font.pixelSize: Style.fs(-3)
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
                                    ThemeAudio.play("confirm");
                                    NotificationState.invoke_action(root.entry, action_chip.modelData);
                                    NotificationState.close_popup_if_empty();
                                }
                            }
                        }
                    }
                }

                Loader {
                    active: root.dialog && root.selected
                    visible: active
                    Layout.topMargin: 4
                    sourceComponent: Ps2.DialogPrompt {
                        entries: [
                            { button: "cross", text: root.focused_valid ? root.actions[root.focused_action].text : "Open", action: () => root.enter() },
                            { key: "d", text: "Dismiss", action: () => NotificationState.dismiss(root.entry) },
                            { button: "start", text: "Close", action: () => { ThemeAudio.play("cancel"); Popups.close(); } }
                        ]
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

    Component {
        id: dq_card
        Weather.DqWindow {
            border.color: root.selected ? Style.caret_color : Style.pal.fg_strong

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 10
                anchors.bottomMargin: 8
                opacity: !root.selected || Style.caret_phase ? 1 : 0
                text: "\u25bc"
                color: root.selected ? Style.caret_color : Style.pal.fg_strong
                font.family: Style.font_family
                font.pixelSize: 8
            }
        }
    }

    Component {
        id: dialogue_card
        Snes.SnesWindow {
            lit: root.selected
        }
    }

    Component {
        id: tile_card
        Modern.CardSurface {
            selected: root.selected
        }
    }

    Component {
        id: notify_card
        Rectangle {
            radius: 6
            color: root.selected ? Style.pal.bg_surface : "transparent"
            border.width: 1
            border.color: root.selected ? Style.caret_color : Qt.tint(Style.frame_color, Qt.alpha(root.accent, 0.7))
        }
    }

    Component {
        id: dialog_card
        Ps2.DialogPanel {
            selected: root.selected
            accent: root.critical ? Style.pal.error : Style.pal.primary_light
        }
    }

    Component {
        id: oasis_card
        Oasis.OasisCard {
            selected: root.selected
            critical: root.critical
        }
    }
}
