import QtQuick
import QtQuick.Layouts

// A module's content: one row on a top or bottom bar, one centred column on a side bar.
// Children set Layout.alignment to Qt.AlignHCenter when `vertical`, else Qt.AlignVCenter.
GridLayout {
    id: root

    property real spacing: 0
    // Taken from the BarModule this sits in.
    property bool vertical: !!parent && !!parent.vertical

    flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rows: root.vertical ? -1 : 1
    columns: root.vertical ? 1 : -1
    rowSpacing: root.spacing
    columnSpacing: root.spacing
}
