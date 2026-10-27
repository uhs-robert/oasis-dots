import QtQuick
import QtQuick.Layouts
import qs.core
import qs.theme
import qs.features.bar
import qs.features.media
import "SettingsScale.js" as SScale

// Settings > Media's preview: the bar's own MediaWell on a patch of island, enlarged, with the current media settings.
// It shows the live player when one plays or is paused on a track, else a MediaSample. The right side is picked as
// Media.qml and Bar.qml pick it, so the battery fallback and the forced position of the split mode and lualine show too.
ColumnLayout {
    id: root

    property var popup: null
    // False while Settings is closed, so the sample stops and cava is not asked for.
    property bool active: true
    property real zoom: 2

    readonly property var screen: root.popup ? root.popup.screen : null
    // A horizontal bar's thickness on this screen; a side bar's would be its width, so it falls back to the style's.
    readonly property int bar_height: {
        if (!root.screen) return Style.bar_height;
        const position = BarSettings.position_on(root.screen.name);
        if (position !== "top" && position !== "bottom") return Style.bar_height;
        return BarSettings.height_for(BarSettings.rule_for(root.screen));
    }
    readonly property bool island_style: !Style.strip_shape && !Style.bar_lualine
    readonly property string forced_right_side: MediaSettings.module_position_only(root.island_style, Style.bar_lualine) ? "position" : ""
    readonly property real pad: Math.round(root.bar_height * 0.3)
    // Shrinks below `zoom` when the enlarged well would not fit the pane.
    readonly property real fit_zoom: SScale.fit_zoom(root.zoom, root.width, island.width)

    spacing: 4

    MediaSample {
        id: sample
        running: sample.replaces_player && root.active
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.ceil(island.height * root.fit_zoom)

        Rectangle {
            id: island
            // Scaled from its own top-left corner, so it is placed by its scaled width.
            x: Math.round((parent.width - island.width * root.fit_zoom) / 2)
            width: well.implicitWidth + root.pad * 2
            height: root.bar_height
            radius: Style.bar_radius(8)
            color: Style.island_fill(Style.bar_side_bg)
            transform: Scale {
                xScale: root.fit_zoom
                yScale: root.fit_zoom
            }

            MediaWell {
                id: well
                anchors.centerIn: parent
                width: well.implicitWidth
                height: well.bar_fit_height(root.bar_height)
                sample: sample.replaces_player ? sample : null
                active: root.active
                right_mode: MediaSettings.right_side(root.forced_right_side, PowerSource.on_ac)
            }
        }
    }

    Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: sample.replaces_player ? "Sample track: nothing is playing" : "Now playing" + (MediaState.active && MediaState.active.identity ? " in " + MediaState.active.identity : "")
        color: root.popup ? root.popup.st.text_dim : Style.text_dim
        elide: Text.ElideRight
        font.family: root.popup ? root.popup.st.font_family : Style.font_family
        font.pixelSize: root.popup ? root.popup.st.fs(-3) : Style.font_size - 3
    }
}
