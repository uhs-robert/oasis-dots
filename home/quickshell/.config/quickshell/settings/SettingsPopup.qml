// home/quickshell/.config/quickshell/settings/SettingsPopup.qml
import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"
import "../services"
import "Sections.js" as Sections

Popup {
    id: root

    popup_name: "settings"
    title: "SETTINGS"
    size_class: "large"
    // The pane keeps 450; the sidebar grows to fit the widest section label in the active style.
    preferred_width: 467 + nav.width / Style.scale
    body_height: Math.max(nav.implicitHeight, root.pane_height) + 24
    reserve_height: root.max_body
    jumps_enabled: true
    search_enabled: true
    footer_hint: root.in_pane && root.pane ? root.pane.shown_hint : "/ find · j/k move · l enter · 1-9 pick · gg/G first/last · q close"

    // The lock's full-screen preview (LockPreview), for the lock section's p key.
    property var previewer: null

    property int nav_index: 0
    property bool in_pane: false
    property string loaded_id: ""
    readonly property var pane: pane_loader.item
    readonly property bool is_open: Popups.open_name === "settings"
    // Last valid pane height, held while a section loads; max_body is the tallest body this open.
    property real pane_height: 0
    property real max_body: 0
    readonly property real pane_implicit: pane_loader.status === Loader.Ready ? pane_loader.implicitHeight : NaN
    onPane_implicitChanged: if (isFinite(root.pane_implicit) && root.pane_implicit > 0) root.pane_height = root.pane_implicit
    onBody_heightChanged: if (isFinite(root.body_height)) root.max_body = Math.max(root.max_body, root.body_height)

    search_rows: root.in_pane && root.pane ? root.pane.search_rows : Sections.list.map(s => s.label + " " + s.group + " " + s.keywords)
    search_cursor: root.in_pane && root.pane ? root.pane.search_cursor : root.nav_index
    onSearch_select: index => {
        if (root.in_pane && root.pane) root.pane.search_select(index);
        else root.nav_index = index;
    }
    onJump_first: root.jump(-1)
    onJump_last: root.jump(1)
    onNav_indexChanged: {
        if (!root.is_open) return;
        load_timer.restart();
        ThemeAudio.play("cursor");
    }

    Timer {
        id: load_timer
        interval: 120
        onTriggered: root.load_section()
    }
    onIs_openChanged: {
        load_timer.stop();
        if (!root.is_open) {
            root.in_pane = false;
            return;
        }
        root.max_body = root.body_height;
        if (!root.apply_request()) {
            root.load_section();
            root.leave_pane();
        }
    }

    function jump(delta) {
        if (root.in_pane && root.pane) root.pane.jump(delta);
        else root.nav_index = delta < 0 ? 0 : Sections.list.length - 1;
    }

    function load_section() {
        const section = Sections.list[root.nav_index];
        if (!section || root.loaded_id === section.id) return;
        root.loaded_id = section.id;
        pane_loader.setSource(Qt.resolvedUrl(section.source), { popup: root });
        pane_fade.restart();
    }

    function enter_pane() {
        load_timer.stop();
        root.load_section();
        if (!root.pane) return;
        root.in_pane = true;
        root.pane.forceActiveFocus();
        ThemeAudio.play("confirm");
    }

    function leave_pane() {
        if (root.in_pane) ThemeAudio.play("cancel");
        root.in_pane = false;
        nav.forceActiveFocus();
    }

    // Selects the section SettingsNav names and enters it; false when none was asked for.
    function apply_request() {
        const index = Sections.index_of(SettingsNav.requested);
        SettingsNav.requested = "";
        if (index < 0) return false;
        root.nav_index = index;
        root.load_section();
        root.enter_pane();
        return true;
    }

    Connections {
        target: SettingsNav
        function onRequestedChanged() {
            if (root.is_open && SettingsNav.requested !== "") root.apply_request();
        }
    }

    FocusScope {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: Math.max(nav.implicitHeight, root.pane_height)
        focus: true

        // Runs after the section: Esc, h and Tab it did not use go back to the sidebar.
        Keys.onPressed: event => {
            if (!root.in_pane || (event.modifiers & Qt.ControlModifier)) return;
            const leave = (event.key === Qt.Key_H && !(event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab || (event.key === Qt.Key_Escape && root.search_query === "");
            if (!leave) return;
            root.leave_pane();
            event.accepted = true;
        }

        Item {
            id: nav
            readonly property real fit: {
                let w = 0;
                for (let i = 0; i < nav_repeater.count; i++) {
                    const item = nav_repeater.itemAt(i);
                    if (item) w = Math.max(w, item.need);
                }
                return w;
            }
            width: Math.max(Style.px(150), Math.ceil(nav.fit))
            implicitHeight: nav_col.implicitHeight
            focus: true

            Keys.onPressed: event => {
                if (event.modifiers & Qt.ControlModifier) return;
                const count = Sections.list.length;
                if (event.key === Qt.Key_J) root.nav_index = root.wrap_index(root.nav_index, 1, 0, count);
                else if (event.key === Qt.Key_K) root.nav_index = root.wrap_index(root.nav_index, -1, 0, count);
                else if (event.key === Qt.Key_L || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) root.enter_pane();
                else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.key - Qt.Key_1 < count) root.nav_index = event.key - Qt.Key_1;
                else return;
                event.accepted = true;
            }

            Column {
                id: nav_col
                width: parent.width
                spacing: 4

                Repeater {
                    id: nav_repeater
                    model: Sections.list

                    Column {
                        id: entry
                        required property int index
                        required property var modelData
                        readonly property bool first: entry.index === 0 || Sections.list[entry.index - 1].group !== entry.modelData.group
                        readonly property real need: 16 + nav_row.inset + nav_row.key_space + nav_layout.implicitWidth

                        width: nav_col.width
                        spacing: 4

                        MenuSection {
                            visible: entry.first
                            width: entry.width
                            topPadding: entry.index === 0 ? 0 : 6
                            label: entry.modelData.group
                        }

                        MenuRow {
                            id: nav_row
                            width: entry.width
                            height: Style.px(28)
                            base_radius: 6
                            selected: entry.index === root.nav_index
                            key: entry.index < 9 ? String(entry.index + 1) : ""

                            RowLayout {
                                id: nav_layout
                                anchors.left: parent.left
                                anchors.leftMargin: 8 + nav_row.inset
                                anchors.right: parent.right
                                anchors.rightMargin: 8 + nav_row.key_space
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                Text {
                                    text: entry.modelData.glyph
                                    color: nav_row.fg(root.st.text_accent)
                                    font.family: root.st.font_family
                                    font.pixelSize: root.st.font_size
                                }

                                RowLabel {
                                    Layout.fillWidth: true
                                    label: entry.modelData.label
                                    color: nav_row.fg(root.st.text_fg)
                                    font.family: root.st.font_family
                                    font.pixelSize: root.st.font_size
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.nav_index = entry.index;
                                    root.enter_pane();
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: divider
            x: nav.width + 8
            width: 1
            height: body.height
            color: Qt.alpha(root.st.text_muted, 0.4)
        }

        // Spans the body's full height so a section can pin content, such as row descriptions, to the bottom.
        Loader {
            id: pane_loader
            anchors.left: divider.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
        }

        NumberAnimation {
            id: pane_fade
            target: pane_loader
            property: "opacity"
            from: 0
            to: 1
            duration: 150
            easing.type: Easing.OutCubic
        }
    }
}
