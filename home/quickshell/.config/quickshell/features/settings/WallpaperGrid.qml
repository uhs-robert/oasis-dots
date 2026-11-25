import QtQuick
import QtQuick.Layouts
import qs.theme

// Look mockup, not a shippable feature: wallpaper thumbnails with a per-monitor pin marker.
// `look` "strip_grid": a preview per monitor on top, a GridView of thumbnails below.
// `look` "hero_strip": one large preview of the cursor image over a single filmstrip row.
// The section owns keys and pins; this item only draws and reports `cursor`.
Item {
    id: root

    required property var st
    property string look: "strip_grid"
    property var images: []
    property var monitors: []
    // monitor key -> pinned path
    property var pins: ({})
    // path each monitor shows now, by monitor name
    property var shown: ({})
    property int cursor: 0
    property int target: 0
    property bool active: false
    readonly property string current_path: root.images[root.cursor] || ""
    readonly property int cell_min: Style.px(150)
    readonly property int cols: Math.max(3, Math.floor(root.width / root.cell_min))
    readonly property real cell_w: Math.floor(root.width / root.cols)
    readonly property real cell_h: Math.round(root.cell_w * 9 / 16) + 4
    readonly property bool hero: root.look === "hero_strip"
    readonly property real strip_h: Math.round(Style.px(160) * 9 / 16) + root.st.fs(-3) + 10

    implicitHeight: root.hero ? hero_frame.height + 6 + Style.px(96) + 4 : root.strip_h + 6 + root.cell_h * 3

    // Monitors whose pin is this path, as 1-based numbers.
    function pinned_on(path) {
        const out = [];
        root.monitors.forEach((m, i) => {
            if (root.pins[m.key] === path) out.push(i + 1);
        });
        return out;
    }

    function ensure_visible() {
        if (root.hero) filmstrip.positionViewAtIndex(root.cursor, ListView.Contain);
        else grid.positionViewAtIndex(root.cursor, GridView.Contain);
    }
    onCursorChanged: root.ensure_visible()
    // The first list lands the cursor mid-view instead of at the top edge.
    onImagesChanged: Qt.callLater(() => {
        if (root.hero) filmstrip.positionViewAtIndex(root.cursor, ListView.Center);
        else grid.positionViewAtIndex(root.cursor, GridView.Center);
    })

    Component {
        id: thumb_cell

        Item {
            id: cell
            required property int index
            required property string modelData
            readonly property bool here: cell.index === root.cursor
            readonly property var pinned_by: root.pinned_on(cell.modelData)
            width: root.hero ? Style.px(160) : root.cell_w
            height: root.hero ? Style.px(96) : root.cell_h

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

                // Selected cell: filename over the bottom edge.
                Rectangle {
                    visible: cell.here
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: name_text.implicitHeight + 4
                    color: Qt.alpha(Theme.bg_shadow, 0.8)

                    Text {
                        id: name_text
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        verticalAlignment: Text.AlignVCenter
                        text: cell.modelData.substring(cell.modelData.lastIndexOf("/") + 1)
                        elide: Text.ElideRight
                        color: root.st.text_fg
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }
                }

                // One badge per monitor that pins this image, numbered like the preview strip.
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
                                text: " " + parent.modelData
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

    // Variant A top: one small preview per monitor; the one the grid pins to has the accent frame.
    Row {
        id: strip
        visible: !root.hero
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.strip_h
        spacing: Style.px(8)

        Repeater {
            model: root.monitors

            Item {
                id: mon
                required property int index
                required property var modelData
                readonly property bool pinned: mon.modelData.key in root.pins
                readonly property string path: mon.pinned ? root.pins[mon.modelData.key] : (root.shown[mon.modelData.name] || "")
                width: Math.min(Style.px(160), Math.floor((strip.width - strip.spacing * (root.monitors.length - 1)) / Math.max(1, root.monitors.length)))
                height: strip.height

                Rectangle {
                    id: mframe
                    width: parent.width
                    height: Math.round(width * 9 / 16)
                    radius: Style.px(4)
                    color: Theme.bg_shadow
                    clip: true
                    border.width: mon.index === root.target ? 2 : 1
                    border.color: mon.index === root.target ? root.st.text_accent : Qt.alpha(root.st.text_muted, 0.4)

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: mon.path !== "" ? WallpaperSettings.url_of(mon.path) : ""
                        sourceSize: Qt.size(320, 180)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    Text {
                        visible: mon.pinned
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 4
                        text: ""
                        color: root.st.text_accent
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-2)
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: mframe.bottom
                    anchors.topMargin: 2
                    text: (mon.index + 1) + " " + mon.modelData.name
                    elide: Text.ElideRight
                    color: mon.index === root.target ? root.st.text_accent : root.st.text_dim
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                }
            }
        }
    }

    GridView {
        id: grid
        visible: !root.hero
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: strip.bottom
        anchors.topMargin: 6
        height: root.cell_h * 3
        cellWidth: root.cell_w
        cellHeight: root.cell_h
        clip: true
        interactive: false
        model: root.hero ? [] : root.images
        delegate: thumb_cell
    }

    // Variant B: the cursor image large, with each monitor's pin listed under it.
    Rectangle {
        id: hero_frame
        visible: root.hero
        width: Math.min(root.width, Math.round(Style.px(300) * 16 / 9))
        height: Math.round(width * 9 / 16)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        radius: Style.px(4)
        color: Theme.bg_shadow
        clip: true
        border.width: 1
        border.color: root.active ? root.st.text_accent : Qt.alpha(root.st.text_muted, 0.4)

        Image {
            anchors.fill: parent
            anchors.margins: 1
            source: root.current_path !== "" ? WallpaperSettings.url_of(root.current_path) : ""
            sourceSize: Qt.size(960, 540)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: hero_row.implicitHeight + 8
            color: Qt.alpha(Theme.bg_shadow, 0.8)

            Row {
                id: hero_row
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                spacing: Style.px(12)

                Repeater {
                    model: root.monitors

                    Text {
                        required property int index
                        required property var modelData
                        readonly property bool here: root.pins[modelData.key] === root.current_path
                        text: (index + 1) + " " + modelData.name + (here ? "  pinned" : "")
                        color: here ? root.st.text_accent : index === root.target ? root.st.text_fg : root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-2)
                        font.bold: index === root.target
                    }
                }
            }
        }
    }

    ListView {
        id: filmstrip
        visible: root.hero
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: hero_frame.bottom
        anchors.topMargin: 6
        height: Style.px(96)
        orientation: ListView.Horizontal
        clip: true
        interactive: false
        model: root.hero ? root.images : []
        delegate: thumb_cell
    }
}
