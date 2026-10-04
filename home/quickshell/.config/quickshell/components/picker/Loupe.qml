// home/quickshell/.config/quickshell/components/picker/Loupe.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../../theme"
import "../../services"
import ".."
import "../snes" as SnesParts
import "../ff7" as Ff7Parts
import "../goldeneye" as Goldeneye
import "../../theme/Watch.js" as Watch
import "loupe" as LoupeSkins

// The region selector's magnifier: a zoomed, skinned view of `source` around `at`, placed beside the cursor.
Item {
    id: root

    required property point at
    required property Item source
    required property real sample_scale
    required property bool pixel_mode
    required property string screen_name
    required property real screen_x
    required property real screen_y
    required property real area_width
    required property real area_height
    required property bool has_sel
    required property rect sel
    required property string pixel_image
    required property size frame_size
    required property bool scan_complete
    required property int scan_step
    required property int scan_steps
    readonly property real lens: Screenshot.lens_size
    readonly property real pad: 6
    readonly property int zoom: Screenshot.zoom
    // Odd, so one buffer pixel sits in the center.
    readonly property int count: Math.floor(root.lens / root.zoom) % 2 === 0 ? Math.floor(root.lens / root.zoom) + 1 : Math.floor(root.lens / root.zoom)
    readonly property int half: (root.count - 1) / 2
    readonly property real sample_half: (root.half + 1) / root.sample_scale
    readonly property real view: root.count * root.zoom
    readonly property int bx: Math.floor(root.at.x * root.sample_scale)
    readonly property int by: Math.floor(root.at.y * root.sample_scale)
    readonly property bool skinned: skin_loader.status === Loader.Ready
    readonly property var skin: root.skinned ? skin_loader.item : null
    readonly property bool own_readout: root.skinned && root.skin.own_readout
    readonly property real flip_gap: root.skinned ? root.skin.flip_gap : root.jrpg ? Math.max(66, root.min_gap) : root.gap
    readonly property var rgb: root.parse_rgb(Screenshot.pixel_hex)
    readonly property bool scope: Style.picker_skin === "scope"
    readonly property bool jrpg: Style.picker_skin === "jrpg"
    readonly property bool goldeneye: Style.picker_skin === "goldeneye"
    readonly property bool scopeitem: Style.picker_skin === "scopeitem"
    readonly property bool scanvisor: Style.picker_skin === "scanvisor"
    readonly property bool nvimfloat: Style.picker_skin === "nvimfloat"
    // Zoom mode raises it so the loupe never sits inside the area it magnifies.
    property real min_gap: 0
    readonly property real gap: Math.max(root.min_gap, root.skinned ? root.skin.gap : root.skin_gap)
    readonly property real skin_gap: root.pokemon ? 34 : root.duckhunt ? 34 : root.materia ? 34 : root.tvosd || root.tiecomp ? 32 : root.scanvisor ? 40 : root.tmux ? 30 : root.nvimfloat ? 30 : root.scope || root.jrpg || root.goldeneye || root.scopeitem ? 36 : 28
    readonly property bool materia: Style.picker_skin === "materia"
    readonly property bool duckhunt: Style.picker_skin === "duckhunt"
    readonly property real nv_row_h: 20
    readonly property real nv_cmd_h: 18
    readonly property real nv_foot_gap: 4
    readonly property bool tmux: Style.picker_skin === "tmux"
    readonly property bool tvosd: Style.picker_skin === "tvosd"
    readonly property bool tiecomp: Style.picker_skin === "tiecomp"

    readonly property bool pokemon: Style.picker_skin === "pokemon"
    readonly property real pk_width: Math.max(250, root.view + root.pk_pad * 2)
    readonly property real pk_pad: 10
    readonly property real pk_lens_gap: 8
    readonly property real pk_line_h: 18
    readonly property real pk_divider_gap: 6
    readonly property real pk_divider_h: 4
    readonly property real pk_header_h: root.pk_line_h * 3
    readonly property real pk_msg_h: root.pk_line_h * 2
    // R/G/B parsed from the swatch's hex readout.
    readonly property var pk_rgb: {
        if (!root.pokemon) return [0, 0, 0];
        const hex = Screenshot.pixel_hex;
        if (hex.length < 7) return [0, 0, 0];
        return [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)];
    }
    // Luminance of the sampled color, 0-1, driving the HP bar fill.
    readonly property real pk_luma: (root.pk_rgb[0] * 0.3 + root.pk_rgb[1] * 0.59 + root.pk_rgb[2] * 0.11) / 255
    function pk_hp_color(ratio) {
        return ratio > 0.5 ? Theme.green : ratio > 0.2 ? Theme.theme_secondary : Theme.red;
    }
    function pk_pad3(v) {
        return String(Math.max(0, Math.min(999, Math.round(v)))).padStart(3, "0");
    }
    function pk_pad4(v) {
        return String(Math.max(0, Math.round(v))).padStart(4, "0");
    }
    readonly property var pk_rows: {
        if (!root.pokemon) return [];
        if (root.pixel_mode) return ["RED   " + root.pk_pad3(root.pk_rgb[0]), "GREEN " + root.pk_pad3(root.pk_rgb[1]), "BLUE  " + root.pk_pad3(root.pk_rgb[2])];
        return ["X " + root.pk_pad4(root.at.x) + " Y " + root.pk_pad4(root.at.y)];
    }
    readonly property real pk_stats_h: root.pk_rows.length * root.pk_line_h
    readonly property var pk_message: {
        if (!root.pokemon) return ["", ""];
        if (root.pixel_mode) return ["Wild " + (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------"), "appeared!"];
        if (root.has_sel) return ["Got a " + Math.round(root.sel.width) + "x" + Math.round(root.sel.height), "shot!"];
        return ["Drag to catch", "an area!"];
    }
    readonly property real jrpg_name_h: 16
    readonly property real jrpg_gap: 6
    readonly property real jrpg_drop: 3
    readonly property real ge_rim: root.lens + 32
    readonly property real ge_strip_gap: 8
    readonly property real ge_strip_h: 52
    readonly property real si_pad: 10
    readonly property real si_ruler_h: 22
    readonly property real si_zbar_w: 30
    readonly property real si_body_gap: 10
    readonly property real si_foot_gap: 8
    readonly property real si_foot_h: 20
    readonly property real sv_pad: 10
    readonly property real sv_header_h: 18
    readonly property real sv_header_gap: 8
    readonly property real sv_card_gap: 17
    readonly property real tmux_pad: 10
    readonly property real tmux_w: Math.max(220, root.view + root.tmux_pad * 2)
    readonly property real tmux_line_h: 18
    readonly property real tmux_gap: 6
    // R/G/B parsed from the pixel-mode hex readout, for the tmux pick output line.
    readonly property var tmux_rgb: {
        const hex = Screenshot.pixel_hex;
        if (hex.length < 7) return [0, 0, 0];
        return [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)];
    }
    readonly property bool sv_complete: root.scan_complete
    readonly property real tv_width: Math.max(290, root.view + root.tv_pad_x * 2)
    readonly property real tv_pad_x: 14
    readonly property real tv_pad_y: 10
    readonly property real tv_header_h: 34
    readonly property real tv_lens_gap: 8
    // R/G/B parsed from the swatch's hex readout.
    readonly property real dh_width: Math.max(300, root.view + root.dh_pad * 2)
    readonly property real dh_pad: 6
    readonly property real dh_gap: 6
    readonly property real dh_hud_h: 40
    readonly property real dh_score_h: 40
    readonly property real dh_lens_size: root.view + root.dh_pad * 2
    readonly property real dh_lens_x: (root.dh_width - root.dh_lens_size) / 2
    readonly property var tv_rgb: {
        if (!root.tvosd) return [0, 0, 0];
        const hex = Screenshot.pixel_hex;
        if (hex.length < 7) return [0, 0, 0];
        return [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)];
    }
    // RED/GREEN/BLUE in pixel mode, H POS/V POS in region mode, then a VOL row for zoom in both.
    readonly property var tv_rows: {
        if (!root.tvosd) return [];
        const rows = root.pixel_mode ? [
            { label: "RED", value: root.tv_rgb[0], ratio: root.tv_rgb[0] / 255, color: Theme.red },
            { label: "GREEN", value: root.tv_rgb[1], ratio: root.tv_rgb[1] / 255, color: Theme.bright_green },
            { label: "BLUE", value: root.tv_rgb[2], ratio: root.tv_rgb[2] / 255, color: Theme.blue }
        ] : [
            { label: "H POS", value: Math.round(root.at.x), ratio: root.at.x / root.area_width, color: Theme.green },
            { label: "V POS", value: Math.round(root.at.y), ratio: root.at.y / root.area_height, color: Theme.green }
        ];
        rows.push({ label: "VOL", value: root.zoom + "x", ratio: 0, vol: true, color: Theme.green });
        return rows;
    }
    readonly property real tc_width: Math.max(252, root.view + root.tc_pad_x * 2)
    readonly property real tc_pad_x: 22
    readonly property real tc_pad_y: 18
    readonly property real tc_header_h: 22
    readonly property real tc_lens_gap: 8
    readonly property real tc_row_h: 18
    // R/G/B parsed from the swatch's hex readout.
    readonly property var tc_rgb: {
        if (!root.tiecomp) return [0, 0, 0];
        const hex = Screenshot.pixel_hex;
        if (hex.length < 7) return [0, 0, 0];
        return [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)];
    }
    // SHLD/HULL/SYS bars in pixel mode, POS/SIZE readouts in region mode, then a RNG row for zoom in both.
    readonly property var tc_rows: {
        if (!root.tiecomp) return [];
        const rows = root.pixel_mode ? [
            { label: "SHLD", value: String(root.tc_rgb[0]), ratio: root.tc_rgb[0] / 255, bar: true, color: Theme.red },
            { label: "HULL", value: String(root.tc_rgb[1]), ratio: root.tc_rgb[1] / 255, bar: true, color: Theme.green },
            { label: "SYS", value: String(root.tc_rgb[2]), ratio: root.tc_rgb[2] / 255, bar: true, color: Theme.blue }
        ] : [
            { label: "POS", value: Math.round(root.screen_x + root.at.x) + "," + Math.round(root.screen_y + root.at.y), bar: false, color: Theme.green },
            { label: "SIZE", value: Math.round(root.sel.width) + "x" + Math.round(root.sel.height), bar: false, color: Theme.green }
        ];
        rows.push({ label: "RNG", value: root.zoom + ".0", bar: false, color: Theme.green });
        return rows;
    }
    // R/G/B parsed from the swatch's hex readout; withheld as 0 until the scan completes.
    readonly property var sv_rgb: {
        if (!root.sv_complete) return [0, 0, 0];
        const hex = Screenshot.pixel_hex;
        if (hex.length < 7) return [0, 0, 0];
        return [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)];
    }
    // Zero-padded global coordinate readout for the watch strip.
    function ge_pad4(v) {
        const n = Math.round(v);
        return (n < 0 ? "-" : "") + String(Math.abs(n)).padStart(4, "0");
    }
    // R/G/B in pixel mode; X/Y (and W/H while dragging) in region mode, values matching the coords readout.
    readonly property var jrpg_rows: {
        if (!root.jrpg) return [];
        if (root.pixel_mode) {
            const hex = Screenshot.pixel_hex;
            const rgb = hex.length >= 7 ? [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)] : [0, 0, 0];
            return [
                { label: "R", value: rgb[0], ratio: rgb[0] / 255, color: Theme.red },
                { label: "G", value: rgb[1], ratio: rgb[1] / 255, color: Theme.green },
                { label: "B", value: rgb[2], ratio: rgb[2] / 255, color: Theme.blue }
            ];
        }
        const rows = [
            { label: "X", value: Math.round(root.screen_x + root.at.x), ratio: root.at.x / root.area_width, color: Theme.theme_primary_light },
            { label: "Y", value: Math.round(root.screen_y + root.at.y), ratio: root.at.y / root.area_height, color: Theme.theme_primary_light }
        ];
        if (root.has_sel) {
            rows.push({ label: "W", value: Math.round(root.sel.width), ratio: root.sel.width / root.area_width, color: Theme.theme_secondary });
            rows.push({ label: "H", value: Math.round(root.sel.height), ratio: root.sel.height / root.area_height, color: Theme.theme_secondary });
        }
        return rows;
    }
    readonly property real jrpg_stats_h: root.jrpg_rows.length > 0 ? root.jrpg_rows.length * 14 + (root.jrpg_rows.length - 1) * 3 : 0
    readonly property real header_h: root.scope ? 20 : root.jrpg ? root.jrpg_name_h + root.jrpg_gap : root.scopeitem ? root.si_ruler_h : root.nvimfloat ? 18 : 0
    readonly property real foot_h: 22
    readonly property real si_body_w: root.view + root.si_body_gap + root.si_zbar_w
    readonly property real mat_width: Math.max(222, root.view + root.mat_pad_x * 2)
    readonly property real mat_pad_x: 14
    readonly property real mat_pad_y: 10
    readonly property real mat_header_h: 28
    readonly property real mat_row_gap: 4
    // R/G/B AP bars in pixel mode; Size (while dragging) and Pos in region mode.
    readonly property var mat_rows: {
        if (!root.materia) return [];
        if (root.pixel_mode) {
            const hex = Screenshot.pixel_hex;
            const rgb = hex.length >= 7 ? [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)] : [0, 0, 0];
            return [
                { label: "R AP", value: String(rgb[0]), ratio: rgb[0] / 255, color: Theme.red, bar: true },
                { label: "G AP", value: String(rgb[1]), ratio: rgb[1] / 255, color: Theme.green, bar: true },
                { label: "B AP", value: String(rgb[2]), ratio: rgb[2] / 255, color: Theme.blue, bar: true }
            ];
        }
        return [
            { label: "Size", value: root.has_sel ? Math.round(root.sel.width) + " x " + Math.round(root.sel.height) : "--", ratio: 0, color: "transparent", bar: false },
            { label: "Pos", value: Math.round(root.screen_x + root.at.x) + ", " + Math.round(root.screen_y + root.at.y), ratio: 0, color: "transparent", bar: false }
        ];
    }
    function parse_rgb(hex) {
        if (hex.length < 7) return [0, 0, 0];
        return [parseInt(hex.substr(1, 2), 16), parseInt(hex.substr(3, 2), 16), parseInt(hex.substr(5, 2), 16)];
    }
    function pad4(v) {
        const n = Math.round(v);
        return (n < 0 ? "-" : "") + String(Math.abs(n)).padStart(4, "0");
    }
    width: root.skinned ? root.skin.implicitWidth : root.goldeneye ? root.ge_rim : root.scopeitem ? root.si_pad * 2 + root.si_body_w : root.view + root.pad * 2 + (root.jrpg ? root.jrpg_drop : 0)
    height: root.skinned ? root.skin.implicitHeight : root.goldeneye ? root.ge_rim + root.ge_strip_gap + root.ge_strip_h : root.scope ? root.view + root.pad * 2 + root.header_h + root.foot_h : root.jrpg ? root.pad + root.header_h + root.view + root.jrpg_gap + root.jrpg_stats_h + root.pad + root.jrpg_drop : root.scopeitem ? root.si_pad + root.si_ruler_h + root.view + root.si_foot_gap + root.si_foot_h + root.si_pad : root.view + root.pad * 2 + coords.implicitHeight + 4 + (root.pixel_mode ? swatch_row.height + 4 : 0)
    x: root.at.x + root.gap + root.width <= root.area_width ? root.at.x + root.gap : root.at.x - root.flip_gap - root.width
    y: root.at.y + root.gap + root.height <= root.area_height ? root.at.y + root.gap : root.at.y - root.gap - root.height

    Rectangle {
        visible: !root.scope && !root.jrpg && !root.goldeneye && !root.scopeitem && !root.scanvisor && !root.tvosd && !root.tmux && !root.nvimfloat && !root.pokemon && !root.duckhunt && !root.materia && !root.tiecomp
        anchors.fill: parent
        radius: Style.frame_radius
        color: Style.frame_color
        border.width: Math.max(1, Style.frame_border_width)
        border.color: Style.frame_border_color
    }

    Loader {
        id: skin_loader
        readonly property string name: Style.picker_skin
        onNameChanged: skin_loader.load()
        Component.onCompleted: skin_loader.load()

        function load() {
            if (skin_loader.name === "") {
                skin_loader.source = "";
                return;
            }
            skin_loader.setSource(Qt.resolvedUrl("loupe/" + skin_loader.name.charAt(0).toUpperCase() + skin_loader.name.slice(1) + ".qml"), {
                loupe: Qt.binding(() => root)
            });
        }
    }

    LoupeLens {
        id: lens_content
        loupe: root
        x: root.goldeneye ? (root.ge_rim - root.view) / 2 : root.scopeitem ? root.si_pad : root.pad
        y: root.goldeneye ? (root.ge_rim - root.view) / 2 : root.scopeitem ? root.si_pad + root.si_ruler_h : root.pad + root.header_h
        visible: !root.skinned && !root.goldeneye
        layer.enabled: root.goldeneye && !root.skinned
        grid_color: root.scanvisor ? Qt.alpha(Theme.cyan, 0.14) : Qt.alpha(Theme.bg_shadow, 0.35)
        center_color: root.scope ? Style.picker_hud : Style.caret_color

    }

    LoupeReadout {
        id: swatch_row
        loupe: root
        visible: !root.own_readout && root.pixel_mode
        opacity: root.skinned || root.jrpg || root.goldeneye || root.scopeitem || root.scanvisor || root.tvosd || root.tmux || root.nvimfloat || root.tiecomp || root.materia || root.duckhunt || root.pokemon ? 0 : 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: coords.top
        anchors.bottomMargin: 2
    }

    Text {
        id: coords
        visible: !root.scope && !root.jrpg && !root.goldeneye && !root.scopeitem && !root.scanvisor && !root.tvosd && !root.tmux && !root.nvimfloat && !root.pokemon && !root.duckhunt && !root.materia && !root.tiecomp
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.pad - 2
        text: Math.round(root.screen_x + root.at.x) + ", " + Math.round(root.screen_y + root.at.y) + "  " + root.zoom + "x"
        color: Style.text_fg
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-4)
    }

}
