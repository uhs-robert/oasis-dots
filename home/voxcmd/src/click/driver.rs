//! One call that captures a window and reads its text: the port of `click-ocr`, whose stream the matcher takes.
use super::capture::{self, CaptureMode, ClickError, Geometry, Tools, WorkDir};
use super::strips::{self, Cut};
use super::{ocr, target_file};
use crate::hypr;
use serde_json::Value;
use std::time::Instant;

pub enum WindowSel {
    Focused,
    StableId(String),
}

pub enum Mode {
    /// Writes click-target: a click will follow.
    Click,
    /// Adds the `#info` line and writes nothing, since nothing will click.
    Explain,
}

pub struct CaptureInfo {
    pub class: String,
    pub mode: CaptureMode,
    pub size: (i64, i64),
    pub image: (i64, i64),
    pub inverted: bool,
    pub strips: usize,
    pub ocr_ms: u64,
}

impl CaptureInfo {
    /// The `#info` line, tab separated.
    pub fn line(&self) -> String {
        format!(
            "#info\tclass={}\tmode={}\tsize={}x{}\timage={}x{}\tscale_x={:.3}\tscale_y={:.3}\tinverted={}\tstrips={}\tocr_ms={}",
            self.class,
            self.mode.name(),
            self.size.0,
            self.size.1,
            self.image.0,
            self.image.1,
            self.image.0 as f64 / self.size.0 as f64,
            self.image.1 as f64 / self.size.1 as f64,
            u8::from(self.inverted),
            self.strips,
            self.ocr_ms,
        )
    }
}

#[allow(dead_code, reason = "window and info are read by screen_text from 2.5c")]
pub struct Captured {
    pub window: Value,
    /// click-ocr's stdout, byte for byte: the `#info` line (Explain only), `#window`, then each strip's `#strip` line
    /// and tesseract's text.
    pub stream: Vec<u8>,
    pub info: CaptureInfo,
}

/// The window's geometry and stable id, None when it is not a window with a position and a size.
fn geometry_of(window: &Value) -> Option<(Geometry, String)> {
    let number = |value: &Value, index: usize| value.as_array()?.get(index)?.as_i64();
    let geometry = Geometry {
        x: number(window.get("at")?, 0)?,
        y: number(window.get("at")?, 1)?,
        w: number(window.get("size")?, 0)?,
        h: number(window.get("size")?, 1)?,
    };
    let stable_id = window.get("stableId").and_then(Value::as_str).unwrap_or("");
    Some((geometry, stable_id.to_string()))
}

pub fn window_line(geometry: Geometry, image: (i64, i64)) -> String {
    format!(
        "#window {} {} {} {} {} {}",
        geometry.x, geometry.y, geometry.w, geometry.h, image.0, image.1
    )
}

pub fn strip_line(cut: &Cut) -> String {
    format!(
        "#strip {} {} {} {}",
        cut.index, cut.crop_top, cut.own_top, cut.own_bottom
    )
}

/// `active` is the window to read when the caller has just asked Hyprland for it already.
pub fn capture_page(
    selection: &WindowSel,
    mode: Mode,
    active: Option<&Value>,
    tools: &Tools,
) -> Result<Captured, ClickError> {
    let window = match (active, selection) {
        (Some(window), _) => Some(window.clone()),
        (None, WindowSel::StableId(id)) => hypr::window_by_stable_id(id),
        (None, WindowSel::Focused) => hypr::active_window(),
    };
    let found = window.and_then(|window| geometry_of(&window).map(|(geometry, id)| (window, geometry, id)));
    let Some((window, geometry, stable_id)) = found else {
        let message = match selection {
            WindowSel::StableId(_) => "no such window",
            WindowSel::Focused => "no focused window",
        };
        return Err(ClickError::new(message, 2));
    };
    if geometry.w <= 0 || geometry.h <= 0 {
        return Err(ClickError::new("focused window has no size", 2));
    }
    let class = window.get("class").and_then(Value::as_str).unwrap_or("").to_string();

    let work = WorkDir::create().map_err(|error| ClickError::new(format!("work directory: {error}"), 1))?;
    let shot = capture::take_shot(tools, work.path(), &stable_id, geometry)?;
    if matches!(mode, Mode::Click) {
        target_file::write(&window).map_err(|error| ClickError::new(format!("click-target: {error}"), 1))?;
    }

    let cuts = strips::plan(shot.image.0, shot.image.1, geometry.w);
    let mean = capture::cut_strips(tools, work.path(), shot.image.0, &cuts)?;
    let inverted = mean < strips::DARK_BELOW;
    let started = Instant::now();
    ocr::read_strips(tools, work.path(), &cuts, inverted).map_err(|_| ClickError::new("ocr failed", 1))?;
    let ocr_ms = u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX);

    let info = CaptureInfo {
        class,
        mode: shot.mode,
        size: (geometry.w, geometry.h),
        image: shot.image,
        inverted,
        strips: cuts.len(),
        ocr_ms,
    };
    let mut stream = Vec::new();
    if matches!(mode, Mode::Explain) {
        stream.extend_from_slice(info.line().as_bytes());
        stream.push(b'\n');
    }
    stream.extend_from_slice(window_line(geometry, shot.image).as_bytes());
    stream.push(b'\n');
    for cut in &cuts {
        stream.extend_from_slice(strip_line(cut).as_bytes());
        stream.push(b'\n');
        // A strip that finished well but left no readable text is a failed read, not an empty strip.
        let text =
            std::fs::read(strips::strip_text_file(work.path(), cut)).map_err(|_| ClickError::new("ocr failed", 1))?;
        stream.extend(text);
    }
    Ok(Captured { window, stream, info })
}
