pragma Singleton
import QtQuick
import Quickshell
import qs.theme
import "FrameGeometry.js" as FrameGeometry

// Each screen's screen frame layout (FrameGeometry.frame_layout), or null with no frame, for whoever places something
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

    function layout_for(screen) {
        if (!Style.screen_frame_on) return null;
        const rule = BarSettings.rule_for(screen);
        const has_bar = rule !== null && rule.bar !== false;
        const bar_edge = has_bar ? (BarSettings.position_for(rule) === "bottom" ? "bottom" : "top") : "";
        return FrameGeometry.frame_layout(screen.width, screen.height, bar_edge, BarSettings.height_for(rule), Object.assign({}, Style.screen_frame_kit, Style.screen_frame_profile, { fill_overlap: Style.islands_translucent ? 0 : 1 }));
    }
}
