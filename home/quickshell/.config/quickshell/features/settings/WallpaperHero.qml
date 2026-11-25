import QtQuick
import QtQuick.Layouts
import qs.core
import qs.theme
import "WallpaperStrip.js" as Strip

// The Wallpaper section's picture area: one large preview of the image at `cursor`, a line with its full file name and
// what each monitor does with it, and a filmstrip of the collection with the cursor cell kept in the middle.
// The section owns the keys and the pins; this item only draws.
ColumnLayout {
    id: root

    required property var st
    property var images: []
    property var monitors: []
    // monitor key -> pinned path
    property var pins: ({})
    property int cursor: 0
    // The monitor Enter pins on, an index into `monitors`.
    property int target: 0
    // True while the keys move the filmstrip; the cursor frames are muted otherwise.
    property bool active: false
    // The file the preview and the name show. It is the cursor image while browsing, and the monitor's own image otherwise,
    // which may not be in the listed collection.
    property string path: ""
    // What the section asks the popup to scroll into view: the filmstrip, not the whole hero, which can be taller than a short pane.
    readonly property Item filmstrip_item: filmstrip
    readonly property real cell_width: Style.px(128)
    readonly property real cell_height: Math.round(root.cell_width * 9 / 16)

    spacing: Style.px(6)

    Rectangle {
        id: hero_frame
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: Math.min(root.width, Math.round(Style.px(300) * 16 / 9))
        Layout.preferredHeight: Math.round(hero_frame.width * 9 / 16)
        radius: Style.px(4)
        color: Theme.bg_shadow
        clip: true
        border.width: 1
        border.color: root.active ? root.st.text_accent : Qt.alpha(root.st.text_muted, 0.4)

        Image {
            anchors.fill: parent
            anchors.margins: 1
            source: root.path !== "" ? WallpaperSettings.url_of(root.path) : ""
            sourceSize: Qt.size(960, 540)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    // The whole name, so the filmstrip cells need none. Middle elision keeps the extension when even this line is short.
    Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: WallpaperSettings.base_name(root.path) + (root.images[root.cursor] === root.path ? "  (" + (root.cursor + 1) + "/" + root.images.length + ")" : "")
        elide: Text.ElideMiddle
        color: root.st.text_fg
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    // Each monitor's state for this image; the target is bold and marked.
    Flow {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        spacing: Style.px(14)

        Repeater {
            model: root.monitors

            Text {
                required property int index
                required property var modelData
                readonly property bool here: root.pins[modelData.key] === root.path
                readonly property bool pinned: modelData.key in root.pins
                readonly property bool is_target: index === root.target
                text: (is_target ? "> " : "") + (index + 1) + " " + modelData.name + (here ? ": pinned here" : pinned ? ": pinned" : ": automatic")
                color: here ? root.st.text_accent : is_target ? root.st.text_fg : root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
                font.bold: is_target
            }
        }
    }

    ListView {
        id: filmstrip
        visible: root.images.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: root.cell_height + 4
        orientation: ListView.Horizontal
        clip: true
        interactive: false
        // The margins give the first and last cell room to reach the middle.
        leftMargin: Math.max(0, (filmstrip.width - root.cell_width) / 2)
        rightMargin: filmstrip.leftMargin
        model: root.images
        contentX: Strip.centre_x(root.cursor, root.cell_width, filmstrip.width)

        // Animates only on AC power and while shown (README: nothing animates on battery or hidden).
        Behavior on contentX {
            enabled: PowerSource.on_ac && root.visible
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        delegate: Item {
            id: cell
            required property int index
            required property string modelData
            readonly property bool here: cell.index === root.cursor
            readonly property var pinned_by: Strip.pinned_on(root.monitors, root.pins, cell.modelData)
            width: root.cell_width
            height: root.cell_height + 4

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Style.px(4)
                color: Theme.bg_shadow
                clip: true
                border.width: cell.here ? 2 : 1
                border.color: cell.here ? (root.active ? root.st.text_accent : root.st.text_muted) : Qt.alpha(root.st.text_muted, 0.3)

                Image {
                    anchors.fill: parent
                    anchors.margins: 2
                    source: WallpaperSettings.url_of(cell.modelData)
                    sourceSize: Qt.size(320, 180)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }

                // One numbered badge per monitor that pins this image, in the order of the monitor line.
                Row {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 3
                    spacing: 2

                    Repeater {
                        model: cell.pinned_by

                        Rectangle {
                            required property int modelData
                            width: pin_text.implicitWidth + 8
                            height: pin_text.implicitHeight + 2
                            radius: Style.px(3)
                            color: root.st.text_accent

                            Text {
                                id: pin_text
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: Theme.bg_shadow
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-3)
                            }
                        }
                    }
                }
            }
        }
    }
}
