import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.features.settings

RowsSection {
    id: root

    section_keys: "r reset value · R reset all"
    footer_hint: "j/k move · H/L change · r reset value · R reset all · h/Esc sections · q close"
    rows: Style.settings.map(def => root.row_for(def))

    function number_values(def) {
        const out = [];
        const count = Math.round((def.max - def.min) / def.step);
        for (let i = 0; i <= count; i++) out.push(Math.round((def.min + i * def.step) * 1000) / 1000);
        const now = Style.option(def.key);
        if (out.indexOf(now) < 0) out.push(now);
        return out.sort((a, b) => a - b);
    }

    readonly property var notes: ({
            device_model: "Which handheld is drawn: Color uses the palette, Original the grey shell.",
            scanlines: "Faint horizontal lines over popups and notifications.",
            glow: "A soft glow around text and frames.",
            glow_tint: "How strongly the glow shows, from 0 to 1.",
            dither: "A dotted pattern over the bar and cards.",
            meter_bloom: "A blurred copy of each meter drawn behind it.",
            caret_blink: "Blink the text cursor in search and input fields.",
            fade_fills: "Selection and title fills fade out to the right.",
            controller_glyphs: "Console buttons for keys: Labeled adds the key, D-pad only arrows and shoulders.",
            watch_colors: "Theme tints the watch from your palette. Classic is the fixed lock-skin green.",
            picker_skin: "Screenshot picker cursor, loupe and targets, from any style, in your palette.",
            overview_skin: "Overview extras: Night Vision's counter, tint and lock-on, or MGS1 Scope's reticle.",
            osd_layout: "Volume and brightness OSD. Watch Dial also adds dials to Volume and Battery.",
            weather_header: "Weather header and Daily view, from any style, drawn in your palette.",
            keeptabs_layout: "KeepTabs Agents and Usage screens, from any style, drawn in your palette.",
            done_anim: "The keeptabs celebration when a session finishes, from any style.",
            wait_anim: "The keeptabs cue when a session waits on you, from any style.",
            toast_enter: "How notification toasts arrive, from any style.",
            screen_frame: "Bands in the bar's colour round the rest of the screen, joined to the bar. Windows round to match while it is on.",
            bar_island_shape: "The outline of the bar's islands, or one strip across the full bar, from any style, drawn in your palette.",
            bar_island_opacity: "How see-through the bar islands' (or the full bar's) backgrounds are; text, icons and borders stay solid.",
            workspace_art: "The bar's workspace indicator, from any style, drawn in your palette.",
            bar_icon_set: "The bar's icons, from any style: pixel art, vector or emoji icons where the set has drawn one, Nerd Font glyphs elsewhere.",
            bar_meeting_marker: "How the bar clock shows an upcoming or running meeting, from any style.",
            font_family: "Font for popups and most text. Each style has its own default.",
            bar_font_family: "Font for the bar. Each style has its own default.",
            font_size: "Base text size in pixels; other sizes scale from it."
        })

    readonly property string locked_note: "Set by Screen frame, which needs the full bar; your choice comes back when the frame is off."

    function row_for(def) {
        if (def.locked !== undefined) return root.locked_row(def);
        const kind = def.type;
        return {
            label: def.label,
            desc: root.notes[def.key] || "",
            values: () => kind === "bool" ? ["on", "off"] : kind === "choice" ? def.choices : root.number_values(def),
            text: v => def.labels ? def.labels[v] : def.percent ? Math.round(v * 100) + "%" : String(v),
            value: () => kind === "bool" ? (Style.option(def.key) ? "on" : "off") : Style.option(def.key),
            set: v => Style.set_option(def.key, kind === "bool" ? v === "on" : v)
        };
    }

    // Shows the fixed text and neither steps nor opens a list.
    function locked_row(def) {
        return {
            label: def.label,
            desc: root.locked_note,
            keys: "",
            values: () => [def.locked],
            text: v => v,
            value: () => def.locked,
            set: v => {},
            cycle: false,
            pick: false
        };
    }

    onExtra_key: event => {
        if (event.key !== Qt.Key_R) return;
        const def = Style.settings[root.cursor];
        if (event.modifiers & Qt.ShiftModifier) Style.reset_options();
        else if (def && def.locked === undefined) Style.reset_option(def.key);
        event.accepted = true;
    }

    header: Text {
        Layout.fillWidth: true
        text: Style.label(Style.saved_name) + " options"
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
