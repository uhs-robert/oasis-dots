import QtQuick
import "BandGeometry.js" as Band

// Draws `source` over w by h except inside `gaps` (each { x, y, w, h }), by drawing it again clipped to each of the rects
// round them. A path cannot be cut open, and a drawer must hide the frame's line along its mouth without painting over it.
Item {
    id: root

    property real w: 0
    property real h: 0
    property var gaps: []
    readonly property var regions: Band.gap_regions(root.w, root.h, root.gaps)
    property Component source: null

    Repeater {
        // A fixed set of slots whose rects follow the gaps, so a drawer opening, closing or resizing moves the clips and never
        // rebuilds the (full-frame) copy drawn in each.
        model: Band.region_slots()

        Item {
            required property int index
            readonly property var region: root.regions[index] || null
            x: region ? region.x : 0
            y: region ? region.y : 0
            width: region ? region.w : 0
            height: region ? region.h : 0
            clip: true

            Loader {
                active: parent.region !== null
                x: -parent.x
                y: -parent.y
                width: root.w
                height: root.h
                sourceComponent: root.source
            }
        }
    }
}
