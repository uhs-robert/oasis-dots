import QtQuick
import qs.features.bar

// The editor's hint bar as a screen-frame drawer, one per screen, for a screen that has the frame: it grows out of the edge
// the bar is not on, like the submap hint bar (features/submap_hints/SubmapHintBar.qml); in monitor select it carries the
// monitor map above the hints and follows the picked screen. A screen without a frame layout keeps HintBox and the floating
// monitor box inside BarEditorWindow; the two never show together.
HintDrawer {
    id: root

    // Whether the content shows the map. It follows the mode only while the drawer is folded: a mode change across monitor
    // select folds the drawer, swaps the content and grows it again, since the drawer cannot resize while open.
    property bool tall: false
    readonly property bool tall_wanted: BarEditor.mode === "monitor"
    // Gates on the content matching the mode too, so closing the editor mid-regrow leaves the drawer folded.
    wanted: BarEditor.keyboard_owner(root.modelData.name) && root.tall === root.tall_wanted
    namespace: "quickshell-bareditor-hints"

    function settle() {
        if (root.tall !== root.tall_wanted && root.progress <= 0) root.tall = root.tall_wanted;
    }
    onTall_wantedChanged: root.settle()
    onProgressChanged: root.settle()

    Item {
        anchors.centerIn: parent
        width: Math.max(root.tall ? map.width : 0, hints.width)
        implicitHeight: (root.tall ? map.height + 10 : 0) + hints.implicitHeight
        MonitorMap {
            id: map
            visible: root.tall
            anchors.horizontalCenter: parent.horizontalCenter
            // A short screen leaves the map a third of its height.
            max_height: root.modelData.height / 3
        }
        HintContent {
            id: hints
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.tall ? map.height + 10 : 0
            carrying: BarEditor.mode === "hidden" && BarEditor.picked !== ""
            vertical: root.bar_item !== null && root.bar_item.vertical
        }
    }
}
