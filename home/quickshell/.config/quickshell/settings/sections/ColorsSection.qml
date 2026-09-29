// home/quickshell/.config/quickshell/settings/sections/ColorsSection.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
import ".."

SettingsPane {
    id: root

    property int selected: 0
    // Set once the user moves; until then the selection follows the active palette as it loads.
    property bool touched: false
    readonly property string picked: Palettes.names[root.selected] || ""

    footer_hint: "/ find · j/k preview · gg/G first/last · 1-9 pick · Enter apply · Esc sections · q close"
    search_rows: Palettes.names.map(n => Palettes.label(n))
    search_cursor: root.selected
    implicitHeight: col.implicitHeight

    // Leaving the pane or closing the popup drops any unapplied preview.
    onLiveChanged: {
        if (root.live) {
            root.touched = false;
            root.resync();
        } else {
            Palettes.restore();
        }
    }
    onPickedChanged: if (root.live && Palettes.ready && root.touched && !root.popup.search_typing) Palettes.preview(root.picked)
    Component.onCompleted: root.resync()
    Component.onDestruction: Palettes.restore()

    function resync() {
        if (!root.touched && Palettes.ready) root.selected = Math.max(0, Palettes.names.indexOf(Palettes.current));
    }

    function search_select(index) {
        root.touched = true;
        root.selected = index;
    }

    function jump(delta) {
        root.touched = true;
        root.selected = delta < 0 ? 0 : Palettes.names.length - 1;
    }

    function apply() {
        if (Palettes.ready) Palettes.apply(root.picked);
    }

    Connections {
        target: Palettes
        function onReadyChanged() { root.resync(); }
        function onNamesChanged() { root.resync(); }
        function onCurrentChanged() { root.resync(); }
    }

    Connections {
        target: root.popup
        function onSearch_typingChanged() {
            if (root.live && Palettes.ready && root.touched && !root.popup.search_typing) Palettes.preview(root.picked);
        }
    }

    Keys.onPressed: event => {
        if (event.modifiers & Qt.ControlModifier) return;
        const count = Palettes.names.length;
        if (event.key === Qt.Key_J || event.key === Qt.Key_K || (event.key >= Qt.Key_1 && event.key <= Qt.Key_9)) root.touched = true;
        if (event.key === Qt.Key_J) root.selected = root.wrap_index(root.selected, 1, count);
        else if (event.key === Qt.Key_K) root.selected = root.wrap_index(root.selected, -1, count);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.apply();
        else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.key - Qt.Key_1 < count) root.selected = event.key - Qt.Key_1;
        else return;
        event.accepted = true;
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 4

        Repeater {
            model: Palettes.names

            MenuRow {
                id: row
                required property int index
                required property string modelData

                Layout.fillWidth: true
                Layout.preferredHeight: Style.px(28)
                base_radius: 6
                selected: root.live && row.index === root.selected
                key: row.index < 9 ? String(row.index + 1) : ""

                RowLayout {
                    anchors.left: parent.left
                    anchors.leftMargin: 8 + row.inset
                    anchors.right: parent.right
                    anchors.rightMargin: 8 + row.key_space
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    RowLabel {
                        Layout.fillWidth: true
                        label: Palettes.label(row.modelData)
                        color: row.fg(root.st.text_fg)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.font_size
                    }

                    Text {
                        text: row.modelData === Palettes.current ? "active" : ""
                        color: row.fg(Theme.ok)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }

                    Row {
                        spacing: 2

                        Repeater {
                            model: Palettes.swatches(row.modelData)

                            Rectangle {
                                required property string modelData
                                width: Style.px(10)
                                height: Style.px(14)
                                radius: 2
                                color: modelData
                                border.width: 1
                                border.color: Qt.alpha("#808080", 0.4)
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.focus_pane();
                        root.touched = true;
                        root.selected = row.index;
                        root.apply();
                    }
                }
            }
        }

        Rectangle {
            id: card
            readonly property var c: Palettes.colors[root.picked] || ({})
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.preferredHeight: card_col.implicitHeight + 16
            color: card.c.bg_core || "transparent"
            border.width: 1
            border.color: card.c.ui_border || "transparent"
            radius: Style.px(4)

            ColumnLayout {
                id: card_col
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Text {
                    text: Palettes.label(root.picked) + " preview"
                    color: card.c.theme_primary || "transparent"
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size
                }

                Text {
                    Layout.fillWidth: true
                    text: "Body text and a <b>strong</b> word"
                    textFormat: Text.RichText
                    color: card.c.fg_core || "transparent"
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }

                Row {
                    spacing: 8

                    Repeater {
                        model: ["theme_primary", "theme_secondary", "theme_accent", "ok", "warning", "error", "info", "hint"]

                        Text {
                            required property string modelData
                            text: modelData.replace("theme_", "")
                            color: card.c[modelData] || "transparent"
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }
                    }
                }

                Row {
                    spacing: 2

                    Repeater {
                        model: ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white", "bright_black", "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan", "bright_white"]

                        Rectangle {
                            required property string modelData
                            width: Style.px(14)
                            height: Style.px(10)
                            radius: 2
                            color: card.c[modelData] || "transparent"
                        }
                    }
                }
            }
        }
    }
}
