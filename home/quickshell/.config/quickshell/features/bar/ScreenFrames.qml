pragma Singleton
import QtQuick
import Quickshell
import qs.theme
import "FrameGeometry.js" as FrameGeometry

// Each screen's screen frame layout (FrameGeometry.frame_layout), or null with no frame, for whoever places something
// against the frame: the frame itself and, by screen, the drawers.
Singleton {
    function layout_for(screen) {
        if (!Style.screen_frame_on) return null;
        const rule = BarSettings.rule_for(screen);
        const has_bar = rule !== null && rule.bar !== false;
        const bar_edge = has_bar ? (BarSettings.position_for(rule) === "bottom" ? "bottom" : "top") : "";
        return FrameGeometry.frame_layout(screen.width, screen.height, bar_edge, BarSettings.height_for(rule), Style.screen_frame_kit);
    }
}
