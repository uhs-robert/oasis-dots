// home/quickshell/.config/quickshell/popups/ScreenshotPopup.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "screenshot"
    title: "Screenshot"
    preferred_width: 250
    footer_hint: "j/k move · Enter run · q close"
    key_help: "j/k move · gg/G first/last · Enter run · r region · z frozen region · s screen · w window · f focused · R record region · W record window · S record screen · F record focused · p pixel · t text · q close"
    body_height: content.implicitHeight + 24
    jumps_enabled: true

    // `select` rows use the themed selector; `flag` rows hand screenshot.sh one of its flags.
    readonly property var base_rows: [
        { section: "Capture", key: "r", label: "Region", glyph: "\u{f0a6d}", select: "", frozen: false },
        { section: "Capture", key: "z", label: "Frozen region", glyph: "\u{f0717}", select: "", frozen: true },
        { section: "Capture", key: "s", label: "Screen", glyph: "\u{f0e51}", flag: "screen" },
        { section: "Capture", key: "w", label: "Window", glyph: "\u{f0614}", flag: "window" },
        { section: "Capture", key: "f", label: "Focused window", glyph: "\u{f08c6}", flag: "focused" },
        { section: "Record", key: "R", label: "Record region", glyph: "\u{f0a6d}", select: "record", frozen: false },
        { section: "Record", key: "W", label: "Record window", glyph: "\u{f0614}", flag: "record-window" },
        { section: "Record", key: "S", label: "Record screen", glyph: "\u{f0e51}", flag: "record-screen" },
        { section: "Record", key: "F", label: "Record focused", glyph: "\u{f08c6}", flag: "record-focused" },
        { section: "Tools", key: "p", label: "Pick pixel color", glyph: "\u{f020a}", flag: "pixel" },
        { section: "Tools", key: "t", label: "Text from region", glyph: "\u{f113a}", select: "ocr", frozen: false }
    ]
    readonly property var rows: root.base_rows

    property int selected: 0

    readonly property bool is_open: Popups.open_name === "screenshot"
    onIs_openChanged: if (is_open) selected = 0
    search_enabled: true
    search_rows: root.rows.map(r => r.label)
    search_cursor: root.selected
    onSearch_select: index => root.selected = index
    onJump_first: root.selected = 0
    onJump_last: root.selected = root.rows.length - 1

    function glyph_color(row) {
        return row.section === "Record" ? Theme.warning : row.section === "Tools" ? Theme.theme_secondary : Theme.theme_primary;
    }

    function choose(index) {
        const row = root.rows[index];
        if (!row) return;
        root.selected = index;
        if (row.select !== undefined) {
            Screenshot.select(row.frozen, row.select);
        } else {
            Screenshot.run_flag(row.flag);
        }
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: rows_col.implicitHeight
        focus: true

        Keys.onPressed: event => {
            const typed = event.modifiers & (Qt.ControlModifier | Qt.AltModifier) ? -1 : root.rows.findIndex(r => r.key === event.text);
            if (event.key === Qt.Key_J) {
                root.selected = root.wrap_index(root.selected, 1, 0, root.rows.length);
            } else if (event.key === Qt.Key_K) {
                root.selected = root.wrap_index(root.selected, -1, 0, root.rows.length);
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.choose(root.selected);
            } else if (typed >= 0) {
                root.choose(typed);
            } else {
                return;
            }
            event.accepted = true;
        }

        ColumnLayout {
            id: rows_col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4

            Repeater {
                model: root.rows

                ColumnLayout {
                    id: row_wrap
                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 2

                    MenuSection {
                        visible: row_wrap.index === 0 || root.rows[row_wrap.index - 1].section !== row_wrap.modelData.section
                        topPadding: row_wrap.index === 0 ? 0 : 6
                        label: row_wrap.modelData.section
                    }

                    MenuRow {
                        id: row
                        Layout.fillWidth: true
                        Layout.preferredHeight: Style.px(28)
                        base_radius: 6
                        selected: row_wrap.index === root.selected
                        key: row_wrap.modelData.key

                        RowLayout {
                            anchors.left: parent.left
                            anchors.leftMargin: 8 + row.inset
                            anchors.right: parent.right
                            anchors.rightMargin: 8 + row.key_space
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Text {
                                text: row_wrap.modelData.glyph
                                color: row.fg(root.glyph_color(row_wrap.modelData))
                                font.family: root.st.font_family
                                font.pixelSize: root.st.font_size
                            }

                            RowLabel {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                label: row_wrap.modelData.label
                                color: row.fg(root.st.text_fg)
                                font.family: root.st.font_family
                                font.pixelSize: root.st.font_size
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.choose(row_wrap.index)
                        }
                    }
                }
            }
        }
    }
}
