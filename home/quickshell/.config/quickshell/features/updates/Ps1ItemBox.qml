pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.theme
import "../../styles/IconSets.js" as IconSets

// Updates as the Resident Evil item box: an examine panel for the selected package over item slots, official packages as crates and AUR packages as herbs.
// Both sections stay on screen. The Official/AUR switch decides which one holds the cursor, and the other is dimmed.
Item {
    id: root

    property var official: []
    property var aur: []
    property bool aur_active: false
    property int selected: 0
    signal picked(bool aur, int index)

    readonly property var st: Style.for_item(root)
    readonly property var list: root.aur_active ? root.aur : root.official
    readonly property var current: root.list[root.selected] || null
    readonly property int columns: Math.max(2, Math.min(4, Math.floor(root.width / Style.px(80))))
    readonly property int gap: 6
    readonly property real slot_width: Math.floor((root.width - root.gap * (root.columns - 1)) / root.columns)
    readonly property real slot_height: Style.px(54)

    // The examine note warns only for kernels, the common update that does nothing until a reboot.
    readonly property var kernels: ["linux", "linux-lts", "linux-zen", "linux-hardened", "linux-rt"]

    function note(pkg) {
        if (!pkg) return "";
        if (root.kernels.indexOf(pkg.name) >= 0) return "Kernel and modules. Restart to use.";
        return root.aur_active ? "Herb from the AUR. Builds from source." : "Item from the official repos.";
    }

    function reveal(index) {
        const grid = root.aur_active ? aur_grid : official_grid;
        const slot = grid.slot_at(index);
        if (!slot) return;
        const top = slot.mapToItem(shelf_column, 0, 0).y;
        // The AUR label scrolls in with the first herb, so the section never shows a herb without its heading.
        const from = root.aur_active && index < root.columns ? aur_label.y : top;
        if (from < shelf.contentY) shelf.contentY = from;
        else if (top + slot.height > shelf.contentY + shelf.height) shelf.contentY = Math.min(top + slot.height - shelf.height, shelf.contentHeight - shelf.height);
    }

    onSelectedChanged: Qt.callLater(root.reveal, root.selected)
    onAur_activeChanged: Qt.callLater(root.reveal, root.selected)

    // An IconSets vector (body plus accent) from the ps1 set, as tall as `size`.
    component ItemGlyph: Shape {
        id: glyph

        property string variant: "official"
        property real size: 24
        property color body: root.st.text_fg
        property color accent: Theme.yellow
        readonly property var vector: IconSets.vector("ps1", "updates", glyph.variant)
        readonly property real unit: glyph.size / 24

        width: glyph.vector ? glyph.vector.w * glyph.unit : 0
        height: glyph.vector ? glyph.vector.h * glyph.unit : 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: glyph.body
            strokeColor: "transparent"
            scale: Qt.size(glyph.unit, glyph.unit)
            PathSvg { path: glyph.vector ? glyph.vector.body : "" }
        }

        ShapePath {
            fillColor: glyph.accent
            strokeColor: "transparent"
            scale: Qt.size(glyph.unit, glyph.unit)
            PathSvg { path: glyph.vector ? glyph.vector.accent : "" }
        }
    }

    // A flat-shaded cardboard crate on a 20x22 grid: one item in the box.
    component Crate: Shape {
        id: crate

        property real size: 22
        readonly property real unit: crate.size / 22
        readonly property color tone: Theme.bright_yellow

        width: 20 * crate.unit
        height: crate.size
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: Qt.darker(crate.tone, 1.45)
            strokeColor: "transparent"
            scale: Qt.size(crate.unit, crate.unit)
            PathSvg { path: "M0 6 L10 1 L20 6 L10 11Z" }
        }

        ShapePath {
            fillColor: Qt.darker(crate.tone, 2.3)
            strokeColor: "transparent"
            scale: Qt.size(crate.unit, crate.unit)
            PathSvg { path: "M0 6 L10 11 V22 L0 17Z" }
        }

        ShapePath {
            fillColor: Qt.darker(crate.tone, 1.8)
            strokeColor: "transparent"
            scale: Qt.size(crate.unit, crate.unit)
            PathSvg { path: "M20 6 L10 11 V22 L20 17Z" }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.darker(crate.tone, 3.6)
            strokeWidth: Math.max(1, crate.unit)
            capStyle: ShapePath.FlatCap
            scale: Qt.size(crate.unit, crate.unit)
            PathSvg { path: "M5 3.5 L15 8.5 V12" }
        }
    }

    component SectionLabel: Text {
        color: root.st.section_fg
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-4)
        font.letterSpacing: 2
        font.capitalization: Font.AllUppercase
    }

    component SlotGrid: Grid {
        id: slot_grid

        property var items: []
        property bool herbs: false
        readonly property bool active: slot_grid.herbs === root.aur_active

        function slot_at(index) {
            return slots.itemAt(index);
        }

        columns: root.columns
        spacing: root.gap
        opacity: slot_grid.active ? 1 : 0.5

        Repeater {
            id: slots
            model: slot_grid.items

            Rectangle {
                id: slot

                required property var modelData
                required property int index
                readonly property bool lit: slot_grid.active && slot.index === root.selected

                width: root.slot_width
                height: root.slot_height
                radius: 4
                color: slot.lit ? root.st.selection_bg : Qt.alpha(Theme.bg_shadow, 0.3)
                border.width: 2
                border.color: slot.lit ? Theme.yellow : Qt.alpha(root.st.frame_border_color, 0.6)

                Loader {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 7
                    sourceComponent: slot_grid.herbs ? herb_glyph : crate_glyph
                }

                Component {
                    id: crate_glyph
                    Crate {
                        size: Style.px(22)
                    }
                }

                Component {
                    id: herb_glyph
                    ItemGlyph {
                        variant: "aur"
                        size: Style.px(22)
                        body: Qt.tint(root.st.text_muted, Qt.alpha(Theme.green, 0.35))
                        accent: Theme.green
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 5
                    width: parent.width - 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: slot.modelData.name
                    color: slot.lit ? root.st.text_strong : root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-4)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.picked(slot_grid.herbs, slot.index)
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        SectionLabel {
            text: "Item box"
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: examine.implicitHeight + 16
            radius: 6
            color: Qt.alpha(Theme.bg_shadow, 0.35)
            border.width: 2
            border.color: root.st.frame_border_color

            RowLayout {
                id: examine
                anchors.fill: parent
                anchors.margins: 8
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: Style.px(66)
                    Layout.preferredHeight: Style.px(66)
                    Layout.alignment: Qt.AlignTop
                    radius: 4
                    color: Qt.alpha(Theme.bg_shadow, 0.5)
                    border.width: 2
                    border.color: Qt.alpha(root.st.frame_border_color, 0.6)

                    ItemGlyph {
                        anchors.centerIn: parent
                        variant: root.aur_active ? "aur" : "official"
                        size: parent.height * 0.62
                        body: root.aur_active ? Qt.tint(root.st.text_muted, Qt.alpha(Theme.green, 0.35)) : Qt.tint(Theme.fg_strong, Qt.alpha(Theme.yellow, 0.15))
                        accent: root.aur_active ? Theme.green : Theme.yellow
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    spacing: 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: root.current ? root.current.name : ""
                            color: root.st.text_strong
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(2)
                            style: Text.Raised
                            styleColor: root.st.text_shadow
                        }

                        Text {
                            text: String(root.selected + 1).padStart(2, "0") + "/" + String(root.list.length).padStart(2, "0")
                            color: Theme.theme_primary_light
                            font.family: root.st.mono_font
                            font.pixelSize: root.st.fs(-4)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideLeft
                        text: root.current ? root.current.old : ""
                        color: root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideLeft
                        text: root.current ? "→ " + root.current.new : ""
                        color: Theme.yellow
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-2)
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 3
                        elide: Text.ElideRight
                        text: root.note(root.current)
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }
                }
            }
        }

        Flickable {
            id: shelf
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: shelf_column.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: shelf_column
                width: shelf.width
                spacing: 6

                SlotGrid {
                    id: official_grid
                    visible: root.official.length > 0
                    items: root.official
                }

                SectionLabel {
                    id: aur_label
                    visible: root.aur.length > 0
                    topPadding: 4
                    text: "Herbs · AUR"
                }

                SlotGrid {
                    id: aur_grid
                    visible: root.aur.length > 0
                    items: root.aur
                    herbs: true
                }
            }
        }
    }
}
