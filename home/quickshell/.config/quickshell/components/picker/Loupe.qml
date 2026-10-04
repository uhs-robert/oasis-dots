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
    width: root.skinned ? root.skin.implicitWidth : root.duckhunt ? root.dh_width : root.goldeneye ? root.ge_rim : root.scopeitem ? root.si_pad * 2 + root.si_body_w : root.tvosd ? root.tv_width : root.tiecomp ? root.tc_width : root.materia ? root.mat_width : root.pokemon ? root.pk_width : root.view + root.pad * 2 + (root.jrpg ? root.jrpg_drop : 0)
    height: root.skinned ? root.skin.implicitHeight : root.duckhunt ? root.dh_lens_size + root.dh_gap + root.dh_hud_h + root.dh_gap + root.dh_score_h : root.goldeneye ? root.ge_rim + root.ge_strip_gap + root.ge_strip_h : root.scope ? root.view + root.pad * 2 + root.header_h + root.foot_h : root.jrpg ? root.pad + root.header_h + root.view + root.jrpg_gap + root.jrpg_stats_h + root.pad + root.jrpg_drop : root.scopeitem ? root.si_pad + root.si_ruler_h + root.view + root.si_foot_gap + root.si_foot_h + root.si_pad : root.tvosd ? root.tv_pad_y * 2 + root.tv_header_h + root.tv_lens_gap * 2 + root.view + tv_rows_col.implicitHeight : root.tiecomp ? root.tc_pad_y * 2 + root.tc_header_h + root.tc_lens_gap * 2 + root.view + tc_rows_col.implicitHeight : root.materia ? root.mat_pad_y * 2 + root.mat_header_h + root.view + root.mat_row_gap + mat_rows_col.implicitHeight : root.pokemon ? root.pk_pad * 2 + root.pk_header_h + root.pk_lens_gap * 2 + root.view + root.pk_stats_h + root.pk_divider_gap * 2 + root.pk_divider_h + root.pk_msg_h : root.view + root.pad * 2 + coords.implicitHeight + 4 + (root.pixel_mode ? swatch_row.height + 4 : 0)
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

    OctagonFrame {
        visible: root.tiecomp
        anchors.fill: parent
    }

    Rectangle {
        visible: root.tvosd
        anchors.fill: parent
        color: Qt.alpha(Theme.bg_shadow, 0.72)
    }

    Rectangle {
        visible: root.duckhunt
        x: root.dh_lens_x
        y: 0
        width: root.dh_lens_size
        height: root.dh_lens_size
        radius: 6
        color: Theme.bg_shadow
        border.width: 3
        border.color: Theme.green
    }

    Rectangle {
        visible: root.pokemon
        anchors.fill: parent
        color: Style.shade_0
        border.width: 2
        border.color: Style.shade_1
        antialiasing: false
    }

    Rectangle {
        visible: root.pokemon
        anchors.fill: parent
        anchors.margins: 3
        color: "transparent"
        border.width: 2
        border.color: Style.shade_2
        antialiasing: false
    }

    Ff7Parts.Ff7Window {
        visible: root.materia
        anchors.fill: parent
    }

    Item {
        id: mat_header
        visible: root.materia
        x: root.mat_pad_x
        y: root.mat_pad_y
        width: root.mat_width - root.mat_pad_x * 2
        height: 22

        MateriaOrb {
            id: mat_orb
            visible: root.pixel_mode
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            color: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : Theme.fg_muted
        }

        Text {
            anchors.left: root.pixel_mode ? mat_orb.right : parent.left
            anchors.leftMargin: root.pixel_mode ? 8 : 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.pixel_mode ? (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") + " Materia" : "Area Materia"
            color: Theme.fg_strong
            style: Text.Raised
            styleColor: Style.text_shadow
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
        }
    }

    Rectangle {
        visible: root.materia
        x: lens_content.x - 2
        y: lens_content.y - 2
        width: lens_content.width + 4
        height: lens_content.height + 4
        radius: 4
        color: "transparent"
        border.width: 2
        border.color: Style.frame_border_color
    }

    LoupeLens {
        id: lens_content
        loupe: root
        x: root.duckhunt ? root.dh_lens_x + root.dh_pad : root.goldeneye ? (root.ge_rim - root.view) / 2 : root.scopeitem ? root.si_pad : root.tvosd ? root.tv_pad_x : root.tiecomp ? root.tc_pad_x : root.materia ? root.mat_pad_x : root.pokemon ? (root.pk_width - root.view) / 2 : root.pad
        y: root.duckhunt ? root.dh_pad : root.goldeneye ? (root.ge_rim - root.view) / 2 : root.scopeitem ? root.si_pad + root.si_ruler_h : root.tvosd ? root.tv_pad_y + root.tv_header_h + root.tv_lens_gap : root.tiecomp ? root.tc_pad_y + root.tc_header_h + root.tc_lens_gap : root.materia ? root.mat_pad_y + root.mat_header_h : root.pokemon ? root.pk_pad + root.pk_header_h + root.pk_lens_gap : root.pad + root.header_h
        visible: !root.skinned && !root.goldeneye
        layer.enabled: root.goldeneye && !root.skinned
        grid_color: root.scanvisor ? Qt.alpha(Theme.cyan, 0.14) : Qt.alpha(Theme.bg_shadow, 0.35)
        center_color: root.duckhunt ? Theme.fg_strong : root.scope ? Style.picker_hud : root.tvosd ? Theme.bright_green : root.tiecomp ? Theme.red : root.materia ? Theme.fg_strong : root.pokemon ? Style.shade_1 : Style.caret_color

        Repeater {
            model: root.tiecomp ? Math.ceil(root.view / 3) : 0

            Rectangle {
                required property int index
                y: index * 3
                width: root.view
                height: 1
                color: Qt.alpha(Theme.green, 0.05)
            }
        }

        CornerBrackets {
            visible: root.tiecomp
            anchors.fill: parent
            color: Theme.green
            inset: 4
            arm: 14
            thickness: 1.5
            all_corners: true
        }

    }

    Rectangle {
        visible: root.tvosd
        x: lens_content.x - 5
        y: lens_content.y - 5
        width: lens_content.width + 10
        height: lens_content.height + 10
        color: "transparent"
        border.width: 6
        border.color: Qt.alpha(Theme.green, 0.25)
    }

    Rectangle {
        visible: root.tvosd
        x: lens_content.x - 2
        y: lens_content.y - 2
        width: lens_content.width + 4
        height: lens_content.height + 4
        color: "transparent"
        border.width: 2
        border.color: Theme.green
    }

    Rectangle {
        visible: root.duckhunt
        x: lens_content.x
        y: lens_content.y + lens_content.height - 16
        width: lens_content.width
        height: 16
        gradient: Gradient {
            GradientStop {
                position: 0
                color: "transparent"
            }
            GradientStop {
                position: 1
                color: Qt.alpha(Theme.green, 0.35)
            }
        }
    }

    Rectangle {
        visible: root.pokemon
        x: lens_content.x - 3
        y: lens_content.y - 3
        width: lens_content.width + 6
        height: lens_content.height + 6
        color: "transparent"
        border.width: 3
        border.color: Style.shade_1
        antialiasing: false
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

    Column {
        id: mat_rows_col
        visible: root.materia
        x: root.mat_pad_x
        y: root.mat_pad_y + root.mat_header_h + root.view + root.mat_row_gap
        width: root.mat_width - root.mat_pad_x * 2
        spacing: 4

        Repeater {
            model: root.materia ? root.mat_rows : []

            Column {
                id: mat_row
                required property var modelData
                width: mat_rows_col.width
                spacing: 2

                Item {
                    width: parent.width
                    height: 14

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: mat_row.modelData.label
                        color: Theme.theme_primary_light
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: mat_row.modelData.value
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                    }
                }

                Rectangle {
                    visible: mat_row.modelData.bar
                    width: parent.width
                    height: 5
                    color: Theme.bg_shadow
                    border.width: 1
                    border.color: Theme.fg_muted

                    Rectangle {
                        x: 1
                        y: 1
                        width: Math.max(0, (parent.width - 2) * Math.max(0, Math.min(1, mat_row.modelData.ratio)))
                        height: parent.height - 2
                        gradient: Gradient {
                            GradientStop { position: 0; color: mat_row.modelData.color }
                            GradientStop { position: 1; color: Theme.fg_strong }
                        }
                    }
                }
            }
        }

        Item {
            width: mat_rows_col.width
            height: 14

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Lv"
                color: Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: String(Screenshot.zoom_index + 1)
                color: Theme.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
            }
        }
    }

    Text {
        id: tv_header
        visible: root.tvosd
        x: root.tv_pad_x
        y: root.tv_pad_y
        text: root.pixel_mode ? "COLOUR " + (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") : root.has_sel ? "ZOOM " + Math.round(root.sel.width) + "x" + Math.round(root.sel.height) : "ZOOM"
        color: Theme.green
        style: Text.Outline
        styleColor: Qt.alpha(Theme.green, 0.6)
        font.family: Style.font_family
        font.pixelSize: 30
    }

    Column {
        id: tv_rows_col
        visible: root.tvosd
        x: root.tv_pad_x
        y: root.tv_pad_y + root.tv_header_h + root.view + root.tv_lens_gap * 2
        width: root.tv_width - root.tv_pad_x * 2
        spacing: 0

        Repeater {
            model: root.tvosd ? root.tv_rows : []

            Item {
                id: tv_row
                required property var modelData
                width: tv_rows_col.width
                height: 20

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 64
                    text: tv_row.modelData.label
                    color: tv_row.modelData.color
                    style: Text.Outline
                    styleColor: Qt.alpha(tv_row.modelData.color, 0.6)
                    font.family: Style.font_family
                    font.pixelSize: 18
                }

                Text {
                    id: tv_value
                    anchors.right: parent.right
                    width: 44
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: String(tv_row.modelData.value)
                    color: tv_row.modelData.color
                    style: Text.Outline
                    styleColor: Qt.alpha(tv_row.modelData.color, 0.6)
                    font.family: Style.font_family
                    font.pixelSize: 18
                }

                Text {
                    readonly property int filled: tv_row.modelData.vol ? Math.min(10, Screenshot.zoom_index * 2 + 2) : Math.round(Math.max(0, Math.min(1, tv_row.modelData.ratio)) * 10)
                    anchors.left: parent.left
                    anchors.leftMargin: 68
                    anchors.right: tv_value.left
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    text: "▮".repeat(filled) + "▯".repeat(10 - filled)
                    color: tv_row.modelData.color
                    style: Text.Outline
                    styleColor: Qt.alpha(tv_row.modelData.color, 0.6)
                    font.family: Style.font_family
                    font.pixelSize: 18
                }
            }
        }
    }

    Text {
        id: tc_header
        visible: root.tiecomp
        x: root.tc_pad_x
        y: root.tc_pad_y
        text: root.pixel_mode ? "TGT " + (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") : root.has_sel ? "TGT " + Math.round(root.sel.width) + "x" + Math.round(root.sel.height) : "TGT AREA"
        color: Theme.green
        font.family: Style.title_font_family
        font.bold: true
        font.pixelSize: 15
        font.letterSpacing: 1
    }

    Column {
        id: tc_rows_col
        visible: root.tiecomp
        x: root.tc_pad_x
        y: root.tc_pad_y + root.tc_header_h + root.view + root.tc_lens_gap * 2
        width: root.tc_width - root.tc_pad_x * 2
        spacing: 0

        Repeater {
            model: root.tiecomp ? root.tc_rows : []

            Item {
                id: tc_row
                required property var modelData
                width: tc_rows_col.width
                height: root.tc_row_h

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    text: tc_row.modelData.label
                    color: tc_row.modelData.color
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                }

                Text {
                    id: tc_value
                    anchors.right: parent.right
                    width: tc_row.modelData.bar ? 30 : 90
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: tc_row.modelData.value
                    color: tc_row.modelData.color
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                }

                Text {
                    visible: tc_row.modelData.bar
                    readonly property int filled: Math.round(Math.max(0, Math.min(1, tc_row.modelData.ratio)) * 10)
                    anchors.left: parent.left
                    anchors.leftMargin: 44
                    anchors.right: tc_value.left
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    text: "▮".repeat(filled) + "▯".repeat(10 - filled)
                    color: tc_row.modelData.color
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                }
            }
        }
    }

    Item {
        id: dh_hud_row
        visible: root.duckhunt
        x: 0
        y: root.dh_lens_size + root.dh_gap
        width: root.dh_width
        height: root.dh_hud_h

        Rectangle {
            id: dh_zoom_box
            x: 0
            y: 0
            height: parent.height
            width: dh_zoom_row.implicitWidth + 16
            radius: 6
            color: Theme.bg_shadow
            border.width: 3
            border.color: Theme.green

            Row {
                id: dh_zoom_row
                anchors.centerIn: parent

                Text {
                    text: "R="
                    color: Theme.bright_green
                    font.family: Style.font_family
                    font.pixelSize: 10
                }

                Text {
                    text: String(root.zoom)
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: 10
                }
            }
        }

        Rectangle {
            id: dh_shot_box
            x: dh_zoom_box.x + dh_zoom_box.width + 8
            y: 0
            height: parent.height
            width: dh_shot_col.implicitWidth + 16
            radius: 6
            color: Theme.bg_shadow
            border.width: 3
            border.color: Theme.green

            Column {
                id: dh_shot_col
                anchors.centerIn: parent
                spacing: 2

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 3

                    Repeater {
                        model: 3

                        Rectangle {
                            width: 5
                            height: 11
                            topLeftRadius: 2
                            topRightRadius: 2
                            color: Theme.bright_yellow
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "SHOT"
                    color: Theme.bright_green
                    font.family: Style.font_family
                    font.pixelSize: 10
                }
            }
        }

        Rectangle {
            id: dh_hit_box
            x: dh_shot_box.x + dh_shot_box.width + 8
            y: 0
            width: Math.max(0, parent.width - dh_hit_box.x)
            height: parent.height
            radius: 6
            color: Theme.bg_shadow
            border.width: 3
            border.color: Theme.green
            clip: true

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: "HIT"
                    color: Theme.bright_green
                    font.family: Style.font_family
                    font.pixelSize: 10
                }

                Repeater {
                    model: dh_hud_row.visible ? 10 : 0

                    DuckIcon {
                        id: hit_duck
                        required property int index
                        fill: Screenshot.recent_picks[hit_duck.index] ? Screenshot.recent_picks[hit_duck.index] : Theme.fg_muted
                    }
                }
            }
        }
    }

    Rectangle {
        id: dh_score_box
        visible: root.duckhunt
        y: root.dh_lens_size + root.dh_gap * 2 + root.dh_hud_h
        x: root.dh_width - dh_score_box.width
        width: dh_score_col.implicitWidth + 16
        height: root.dh_score_h
        radius: 6
        color: Theme.bg_shadow
        border.width: 3
        border.color: Theme.green

        Column {
            id: dh_score_col
            anchors.centerIn: parent
            spacing: 2

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.pixel_mode
                spacing: 4

                Rectangle {
                    width: 10
                    height: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : Theme.bg_shadow
                    border.width: 1
                    border.color: Theme.fg_strong
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex.substring(1) : "------"
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: 10
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.pixel_mode
                text: root.has_sel ? Math.round(root.sel.width) + "x" + Math.round(root.sel.height) : String(Math.round(root.screen_x + root.at.x)).padStart(4, "0") + String(Math.round(root.screen_y + root.at.y)).padStart(4, "0")
                color: Theme.fg_strong
                font.family: Style.font_family
                font.pixelSize: 10
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SCORE"
                color: Theme.bright_green
                font.family: Style.font_family
                font.pixelSize: 10
            }
        }
    }

    Column {
        id: pk_header_col
        visible: root.pokemon
        x: root.pk_pad
        y: root.pk_pad
        width: root.pk_width - root.pk_pad * 2
        spacing: 0

        Text {
            width: parent.width
            height: root.pk_line_h
            text: root.pixel_mode ? (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") : "AREA"
            color: Style.text_fg
            font.family: Style.mono_font
            font.pixelSize: 12
        }

        Item {
            width: parent.width
            height: root.pk_line_h

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: ":L" + root.zoom
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: 12
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.pixel_mode && root.has_sel
                text: Math.round(root.sel.width) + "x" + Math.round(root.sel.height)
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: 12
            }
        }

        Item {
            id: pk_hp_row
            width: parent.width
            height: root.pk_line_h

            Text {
                id: pk_hp_label
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "HP:"
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: 12
            }

            Rectangle {
                id: pk_hp_bar
                anchors.left: pk_hp_label.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 8
                radius: 4
                color: "transparent"
                border.width: 1
                border.color: Style.shade_1

                Rectangle {
                    x: 1
                    y: 1
                    width: Math.max(0, Math.round((pk_hp_bar.width - 2) * Math.min(1, root.pk_luma)))
                    height: pk_hp_bar.height - 2
                    radius: 3
                    color: root.pk_hp_color(root.pk_luma)
                }
            }
        }
    }

    Column {
        id: pk_stats_col
        visible: root.pokemon
        x: root.pk_pad
        y: root.pk_pad + root.pk_header_h + root.pk_lens_gap + root.view + root.pk_lens_gap
        width: root.pk_width - root.pk_pad * 2
        spacing: 0

        Repeater {
            model: root.pokemon ? root.pk_rows : []

            Text {
                required property string modelData
                width: pk_stats_col.width
                height: root.pk_line_h
                text: modelData
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: 12
            }
        }
    }

    Column {
        id: pk_divider
        visible: root.pokemon
        x: root.pk_pad
        y: pk_stats_col.y + root.pk_stats_h + root.pk_divider_gap
        width: root.pk_width - root.pk_pad * 2
        spacing: 2

        Rectangle {
            width: parent.width
            height: 1
            color: Style.shade_1
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Style.shade_1
        }
    }

    Column {
        id: pk_message_col
        visible: root.pokemon
        x: root.pk_pad
        y: pk_divider.y + root.pk_divider_h + root.pk_divider_gap
        width: root.pk_width - root.pk_pad * 2
        spacing: 0

        Repeater {
            model: root.pokemon ? root.pk_message : []

            Text {
                required property string modelData
                width: pk_message_col.width
                height: root.pk_line_h
                text: modelData
                color: Style.text_fg
                font.family: Style.mono_font
                font.pixelSize: 12
            }
        }
    }
}
