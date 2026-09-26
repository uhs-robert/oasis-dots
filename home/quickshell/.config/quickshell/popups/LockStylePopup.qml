// home/quickshell/.config/quickshell/popups/LockStylePopup.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import "../components"
import "../theme"
import "../services"
import "../lock"
import "../lock/Tints.js" as Tints

Popup {
    id: root

    popup_name: "lockscreen"
    title: "LOCK SCREEN"
    preferred_width: 280
    footer_hint: "Tab screen/tint · j/k preview · gg/G first/last · 1-9 pick · Enter apply · p full view · q close"
    body_height: content.implicitHeight + 24
    jumps_enabled: true
    sub_views: ["Screen", "Tint"]

    // The lock's full-screen preview (LockPreview); fake state only, never the session lock.
    property var previewer: null

    property int screen_index: 0
    property int tint_index: 0
    readonly property bool on_tint: root.current_sub === 1

    readonly property var skin_files_list: {
        const out = [];
        for (let i = 0; i < skin_files.count; i++) out.push(skin_files.get(i, "fileName"));
        return out;
    }
    readonly property var screens: ["follow", "simple"].concat(Style.names.filter(n => root.has_skin(n)))
    readonly property var tints: Style.lock_tints
    readonly property string preview_screen: root.screens[root.screen_index] || "follow"
    readonly property string preview_tint: root.tints[root.tint_index] || "primary"
    // What the highlighted row draws: a style with no skin shows the simple screen.
    readonly property string preview_skin: {
        const n = root.preview_screen === "follow" ? Style.saved_name : root.preview_screen;
        return root.has_skin(n) ? n : "simple";
    }

    readonly property bool is_open: Popups.open_name === "lockscreen"
    onIs_openChanged: {
        if (!is_open) {
            skin_loader.source = "";
            return;
        }
        root.screen_index = Math.max(0, root.screens.indexOf(Style.lock_style));
        root.tint_index = Math.max(0, root.tints.indexOf(Style.lock_tint));
        root.load();
    }
    onPreview_skinChanged: if (is_open) root.load()
    onJump_first: root.move_to(0)
    onJump_last: root.move_to(root.row_count() - 1)

    function has_skin(style_name) {
        return root.skin_files_list.indexOf(style_name.charAt(0).toUpperCase() + style_name.slice(1) + ".qml") >= 0;
    }

    function screen_label(name) {
        return name === "follow" ? "Follow bar style" : name === "simple" ? "Simple" : Style.label(name);
    }

    function row_count() {
        return root.on_tint ? root.tints.length : root.screens.length;
    }

    function move_to(i) {
        if (i < 0 || i >= root.row_count()) return;
        if (root.on_tint) root.tint_index = i;
        else root.screen_index = i;
    }

    function load() {
        const url = root.preview_skin === "simple" ? Qt.resolvedUrl("../lock/LockScreen.qml") : Qt.resolvedUrl("../lock/skins/" + root.preview_skin.charAt(0).toUpperCase() + root.preview_skin.slice(1) + ".qml");
        skin_loader.setSource(url, { ctx: fake });
        if (skin_loader.status === Loader.Error) skin_loader.setSource(Qt.resolvedUrl("../lock/LockScreen.qml"), { ctx: fake });
    }

    function apply() {
        if (root.on_tint) Style.set_lock_tint(root.preview_tint);
        else Style.set_lock_style(root.preview_screen);
    }

    function open_full() {
        if (root.previewer) root.previewer.open(root.preview_skin, root.preview_tint);
    }

    FolderListModel {
        id: skin_files
        folder: Qt.resolvedUrl("../lock/skins")
        nameFilters: ["*.qml"]
        showDirs: false
    }

    LockCtx {
        id: fake
        typing: true
        tint: root.preview_tint
    }

    Connections {
        target: root.previewer
        function onShownChanged() {
            if (root.previewer && !root.previewer.shown && root.is_open) root.focus_active_view();
        }
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: col.implicitHeight
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_J) {
                root.move_to(root.wrap_index(root.on_tint ? root.tint_index : root.screen_index, 1, 0, root.row_count()));
            } else if (event.key === Qt.Key_K) {
                root.move_to(root.wrap_index(root.on_tint ? root.tint_index : root.screen_index, -1, 0, root.row_count()));
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.apply();
            } else if (event.key === Qt.Key_P) {
                root.open_full();
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                root.move_to(event.key - Qt.Key_1);
            } else {
                return;
            }
            event.accepted = true;
        }

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4

            Rectangle {
                id: thumb
                readonly property real screen_w: root.screen ? root.screen.width : 1920
                readonly property real screen_h: root.screen ? root.screen.height : 1080

                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(width * screen_h / screen_w)
                Layout.bottomMargin: 6
                color: Theme.bg_shadow
                border.width: 1
                border.color: root.st.frame_border_color
                radius: Style.px(4)
                clip: true

                Loader {
                    id: skin_loader
                    width: thumb.screen_w
                    height: thumb.screen_h
                    scale: (thumb.width - 2) / thumb.screen_w
                    transformOrigin: Item.TopLeft
                    x: 1
                    y: 1
                }
            }

            MenuSection {
                label: "Screen"
                color: root.on_tint ? root.st.section_fg : root.st.text_strong
            }

            Repeater {
                model: root.screens

                MenuRow {
                    id: screen_row
                    required property int index
                    required property string modelData

                    Layout.fillWidth: true
                    height: Style.px(26)
                    base_radius: 6
                    selected: !root.on_tint && index === root.screen_index
                    key: !root.on_tint && index < 9 ? String(index + 1) : ""

                    RowLayout {
                        anchors.left: parent.left
                        anchors.leftMargin: 8 + screen_row.inset
                        anchors.right: parent.right
                        anchors.rightMargin: 8 + screen_row.key_space
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        RowLabel {
                            Layout.fillWidth: true
                            label: root.screen_label(screen_row.modelData)
                            color: screen_row.fg(root.st.text_fg)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size
                        }

                        Text {
                            readonly property bool active: screen_row.modelData === Style.lock_style
                            text: active ? "active" : screen_row.modelData === "follow" ? Style.label(Style.saved_name) : ""
                            color: active ? screen_row.fg(Theme.ok) : screen_row.fg(root.st.text_dim)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.current_sub = 0;
                            root.screen_index = screen_row.index;
                            root.apply();
                        }
                    }
                }
            }

            MenuSection {
                Layout.topMargin: 6
                label: "Tint"
                color: root.on_tint ? root.st.text_strong : root.st.section_fg
            }

            Repeater {
                model: root.tints

                MenuRow {
                    id: tint_row
                    required property int index
                    required property string modelData

                    Layout.fillWidth: true
                    height: Style.px(26)
                    base_radius: 6
                    selected: root.on_tint && index === root.tint_index
                    key: root.on_tint ? String(index + 1) : ""

                    RowLayout {
                        anchors.left: parent.left
                        anchors.leftMargin: 8 + tint_row.inset
                        anchors.right: parent.right
                        anchors.rightMargin: 8 + tint_row.key_space
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Rectangle {
                            implicitWidth: Style.px(10)
                            implicitHeight: Style.px(10)
                            radius: Style.px(2)
                            color: Tints.pair(Theme, tint_row.modelData)[1]
                        }

                        RowLabel {
                            Layout.fillWidth: true
                            label: tint_row.modelData.charAt(0).toUpperCase() + tint_row.modelData.slice(1)
                            color: tint_row.fg(root.st.text_fg)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size
                        }

                        Text {
                            text: tint_row.modelData === Style.lock_tint ? "active" : ""
                            color: tint_row.fg(Theme.ok)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.current_sub = 1;
                            root.tint_index = tint_row.index;
                            root.apply();
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: "The login screen will follow these too (#291)."
                wrapMode: Text.WordWrap
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-3)
            }
        }
    }
}
