import QtQuick
import QtQuick.Layouts
import qs.ui.menu
import qs.theme
import "SettingsScale.js" as SScale

// A table row: a name and three columns (Installed, Local review, Merge gate). The two editable columns are
// 0 (local) and 1 (gate); `column` marks the one the cursor is on. With `header` it draws the column titles instead.
MenuRow {
    id: root

    property bool header: false
    property string label: ""
    property string installed_text: ""
    property string local_text: ""
    property string gate_text: ""
    property bool local_editable: true
    property int column: 0
    readonly property bool hovered: mouse_area.containsMouse
    readonly property int bump: SScale.bump_of(root)
    readonly property real installed_width: Style.px(90)
    readonly property real value_width: Style.px(130)
    readonly property color value_fg: {
        const c = SScale.lifted(root.st.text_dim, root.st.text_fg, 0.6);
        return Qt.rgba(c[0], c[1], c[2], c[3]);
    }

    // The column clicked (0 local, 1 gate) and the direction, by the click's half of that cell.
    signal stepped(int column, int delta)

    Layout.fillWidth: true
    Layout.preferredHeight: Style.px(28) + SScale.pitch_extra(root.bump)
    base_radius: 6

    // One cell: the selected editable cell shows its arrows, a read-only one is dimmed.
    component Cell: Text {
        property bool active: false
        property bool editable: true
        Layout.preferredWidth: root.value_width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: root.header ? root.st.text_dim : root.fg(!editable ? root.st.text_dim : active ? root.st.toggle_on : root.value_fg)
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2) + root.bump
        font.bold: active && !root.header
    }

    RowLayout {
        id: row_layout
        anchors.left: parent.left
        anchors.leftMargin: 8 + root.inset
        anchors.right: parent.right
        anchors.rightMargin: 8 + root.key_space
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        RowLabel {
            Layout.fillWidth: true
            label: root.header ? "Reviewer" : root.label
            color: root.header ? root.st.text_dim : root.fg(root.st.text_fg)
            font.family: root.st.font_family
            font.pixelSize: (root.header ? root.st.fs(-2) : root.st.font_size) + root.bump
            searchable: !root.header
        }

        Text {
            Layout.preferredWidth: root.installed_width
            horizontalAlignment: Text.AlignHCenter
            text: root.header ? "Installed" : root.installed_text
            color: root.header ? root.st.text_dim : root.fg(root.value_fg)
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2) + root.bump
        }

        Cell {
            text: root.header ? "Local review" : root.selected && root.column === 0 && root.local_editable ? "‹ " + root.local_text + " ›" : root.local_text
            active: root.selected && root.column === 0
            editable: root.local_editable || root.header
        }

        Cell {
            text: root.header ? "Merge gate" : root.selected && root.column === 1 ? "‹ " + root.gate_text + " ›" : root.gate_text
            active: root.selected && root.column === 1
        }
    }

    MouseArea {
        id: mouse_area
        anchors.fill: parent
        enabled: !root.header
        hoverEnabled: true
        onClicked: mouse => {
            const gate_left = row_layout.x + row_layout.width - root.value_width;
            const local_left = gate_left - row_layout.spacing - root.value_width;
            const column = mouse.x >= gate_left ? 1 : mouse.x >= local_left ? 0 : root.column;
            const left = column === 1 ? gate_left : local_left;
            root.stepped(column, mouse.x < left + root.value_width / 2 ? -1 : 1);
        }
    }
}
