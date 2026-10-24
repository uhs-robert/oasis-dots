pragma Singleton
import QtQuick
import Quickshell
import qs.theme
import "../../ui/frames/FrameGeometry.js" as FrameGeometry
import "BarLayout.js" as BarLayout

// Each screen's screen frame layout (FrameGeometry.frame_layout), or null with no frame (or a side bar), for whoever places something
// against the frame: the frame itself and, by screen, the drawers.
Singleton {
    id: root

    // Each screen's translucent drawers' windows, by popup (FrameGeometry.drawer_windows_with). The frame and the bar's strip
    // leave their rim and inset line out under them, since a drawer draws its own over the one translucent fill.
    property var drawer_windows: ({})

    function set_drawer_window(screen_name, key, rect) {
        root.drawer_windows = FrameGeometry.drawer_windows_with(root.drawer_windows, screen_name, key, rect);
    }

    function drawer_rects(screen_name) {
        return FrameGeometry.drawer_window_rects(root.drawer_windows, screen_name);
    }

    // The screen's bar edge, "" with no bar.
    function position_for_screen(screen) {
        const rule = BarSettings.rule_for(screen);
        return rule !== null && rule.bar !== false ? BarSettings.position_for(rule) : "";
    }

    function layout_for(screen) {
        const rule = BarSettings.rule_for(screen);
        const position = root.position_for_screen(screen);
        const has_bar = position !== "";
        if (!BarLayout.draws_frame(Style.screen_frame_on, position)) return null;
        const bar_edge = position === "bottom" ? "bottom" : has_bar ? "top" : "";
        return FrameGeometry.frame_layout(screen.width, screen.height, bar_edge, BarSettings.height_for(rule), Object.assign({}, Style.screen_frame_kit, Style.screen_frame_profile, { fill_overlap: Style.islands_translucent ? 0 : 1 }));
    }

    // Whether any screen draws a frame, for what shapes the system around it (Hyprland's window rules, app corners).
    readonly property bool any_frame: BarLayout.any_draws_frame(Style.screen_frame_on, Quickshell.screens.map(s => root.position_for_screen(s)))

    // The hole's outline as points in the hole's own coordinates (its top-left corner at 0, 0), for a surface that fills
    // the hole and must keep the frame's corner profile. Empty with no frame.
    function hole_outline(screen) {
        const lay = root.layout_for(screen);
        if (!lay) return [];
        const hole = FrameGeometry.hole_rect(lay), flip = lay.edge === "bottom";
        return FrameGeometry.hole_loop(lay).map(p => Qt.point(p[0] - hole.x, (flip ? lay.depth - p[1] : p[1]) - hole.y));
    }
}
