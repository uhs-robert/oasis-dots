//! Taking the screenshot of a window and checking that its pixels can be mapped back to the screen.
use super::strips::{self, Cut};
use crate::process::{self, RemovedOnSignal};
use std::ffi::{CString, OsString};
use std::os::unix::ffi::OsStringExt;
use std::path::{Path, PathBuf};
use std::process::Command;

/// The external programs as a command line to start with. Tests put `sh <stub>` there: running a script they just
/// wrote would fail now and then with ETXTBSY when another test thread forks while the file is still open for writing.
pub struct Tools {
    pub grim: Vec<OsString>,
    pub magick: Vec<OsString>,
    pub tesseract: Vec<OsString>,
}

impl Default for Tools {
    fn default() -> Self {
        let named = |name: &str| vec![OsString::from(name)];
        Self {
            grim: named("grim"),
            magick: named("magick"),
            tesseract: named("tesseract"),
        }
    }
}

/// A command for a tool, its leading arguments already in place.
pub fn command_of(tool: &[OsString]) -> Command {
    let mut command = Command::new(&tool[0]);
    command.args(&tool[1..]);
    command
}

/// What a failed capture says and exits with.
#[derive(Debug, PartialEq, Eq)]
pub struct ClickError {
    pub message: String,
    pub code: i32,
}

impl ClickError {
    pub fn new(message: impl Into<String>, code: i32) -> Self {
        Self {
            message: message.into(),
            code,
        }
    }
}

impl std::fmt::Display for ClickError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

/// The private directory the screenshot and the text it holds live in, removed when this drops and, through
/// `RemovedOnSignal`, when voxcmd is stopped: a signal skips every `Drop`.
pub struct WorkDir {
    path: PathBuf,
    _removed_on_signal: RemovedOnSignal,
}

impl WorkDir {
    pub fn create() -> std::io::Result<Self> {
        let base = std::env::var_os("XDG_RUNTIME_DIR")
            .filter(|dir| !dir.is_empty())
            .unwrap_or_else(|| "/tmp".into());
        let mut template = PathBuf::from(base)
            .join("voxcmd-click.XXXXXX")
            .into_os_string()
            .into_vec();
        template.push(0);
        let mut template = CString::from_vec_with_nul(template)
            .map_err(|_| std::io::Error::other("the runtime directory name holds a NUL"))?
            .into_bytes_with_nul();
        // SAFETY: mkdtemp rewrites the XXXXXX of a NUL-terminated buffer it is given the whole of.
        if unsafe { libc::mkdtemp(template.as_mut_ptr().cast()) }.is_null() {
            return Err(std::io::Error::last_os_error());
        }
        template.pop();
        let path = PathBuf::from(OsString::from_vec(template));
        let mut names = vec!["shot.ppm".to_string()];
        for index in 0..strips::MOST_STRIPS {
            names.push(format!("strip{index}.pgm"));
            names.push(format!("strip{index}.tsv"));
        }
        let removed_on_signal = RemovedOnSignal::directory(&path, &names);
        Ok(Self {
            path,
            _removed_on_signal: removed_on_signal,
        })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for WorkDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

/// The window as Hyprland places it: where it is and how big, in logical pixels.
#[derive(Clone, Copy, Debug)]
pub struct Geometry {
    pub x: i64,
    pub y: i64,
    pub w: i64,
    pub h: i64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CaptureMode {
    Toplevel,
    Region,
}

impl CaptureMode {
    pub fn name(self) -> &'static str {
        match self {
            Self::Toplevel => "toplevel",
            Self::Region => "region",
        }
    }
}

/// The last line a failed program said, or `fallback`.
fn last_line_or(stderr: &str, fallback: &str) -> String {
    stderr
        .lines()
        .rev()
        .find(|line| !line.trim().is_empty())
        .unwrap_or(fallback)
        .to_string()
}

/// Native scale, no `-s`: a downscaled capture of a scaled monitor loses words. The real scale comes from the image
/// size. Capturing the toplevel (`-T`, by Hyprland's stableId) reads the window's own buffer; a screen region would
/// composite it over the wallpaper, which shows through translucent windows and costs OCR words.
fn grim_toplevel(tools: &Tools, stable_id: &str, shot: &Path) -> bool {
    if stable_id.is_empty() {
        return false;
    }
    let mut command = command_of(&tools.grim);
    command.args(["-t", "ppm", "-T", stable_id]).arg(shot);
    process::run_to_end(&mut command).is_ok_and(|outcome| outcome.code() == Some(0))
}

fn grim_region(tools: &Tools, window: Geometry, shot: &Path) -> Result<(), ClickError> {
    let mut command = command_of(&tools.grim);
    // One argument, with a space inside.
    command
        .args(["-t", "ppm", "-g"])
        .arg(format!("{},{} {}x{}", window.x, window.y, window.w, window.h))
        .arg(shot);
    let outcome = process::run_to_end(&mut command).map_err(|_| ClickError::new("capture failed", 1))?;
    if outcome.code() == Some(0) {
        Ok(())
    } else {
        Err(ClickError::new(last_line_or(&outcome.stderr, "capture failed"), 1))
    }
}

/// The size in the PPM header, "P6\n<w> <h>\n255\n", which is followed by raw pixels.
pub fn ppm_size(path: &Path) -> Option<(i64, i64)> {
    use std::io::Read;
    let mut head = [0u8; 32];
    let count = std::fs::File::open(path).ok()?.read(&mut head).ok()?;
    let text = String::from_utf8_lossy(&head[..count]);
    let mut tokens = text.split_whitespace();
    tokens.next()?;
    let width = tokens.next()?.parse().ok()?;
    let height = tokens.next()?.parse().ok()?;
    Some((width, height))
}

/// Whether the image's horizontal and vertical scales against the window agree.
pub fn scale_is_uniform(image: (i64, i64), window: Geometry) -> bool {
    let x = image.0 as f64 / window.w as f64;
    let y = image.1 as f64 / window.h as f64;
    let difference = (x - y).abs();
    difference <= strips::SCALE_TOLERANCE * x.max(y)
}

pub struct Shot {
    pub mode: CaptureMode,
    pub image: (i64, i64),
}

/// Captures the window into `shot.ppm` of the work directory. A toplevel capture whose shape is not the window's (a
/// client drawing at its own size) cannot be mapped to the screen, so the region is tried; if that does not fit
/// either, the window cannot be read.
pub fn take_shot(tools: &Tools, work: &Path, stable_id: &str, window: Geometry) -> Result<Shot, ClickError> {
    let shot = work.join("shot.ppm");
    let read_size = || ppm_size(&shot).ok_or_else(|| ClickError::new("capture does not match the window's shape", 1));
    let mut mode = CaptureMode::Toplevel;
    let mut image = None;
    if grim_toplevel(tools, stable_id, &shot) {
        image = Some(read_size()?).filter(|image| scale_is_uniform(*image, window));
    }
    if image.is_none() {
        mode = CaptureMode::Region;
        grim_region(tools, window, &shot)?;
        image = Some(read_size()?);
    }
    let image = image.unwrap_or_default();
    if !scale_is_uniform(image, window) {
        return Err(ClickError::new("capture does not match the window's shape", 1));
    }
    Ok(Shot { mode, image })
}

/// Grays and cuts the shot into the strips, deletes it, and returns the mean luminance of the whole image.
pub fn cut_strips(tools: &Tools, work: &Path, image_w: i64, cuts: &[Cut]) -> Result<f64, ClickError> {
    let mut command = command_of(&tools.magick);
    command.args(strips::magick_cut_args(work, image_w, cuts));
    let outcome = process::run_to_end(&mut command).map_err(|_| ClickError::new("image processing failed", 1))?;
    if outcome.code() != Some(0) {
        return Err(ClickError::new(
            last_line_or(&outcome.stderr, "image processing failed"),
            1,
        ));
    }
    let _ = std::fs::remove_file(work.join("shot.ppm"));
    // A mean that does not parse reads as dark, as the awk's string comparison did for an empty one.
    Ok(outcome.stdout.trim().parse().unwrap_or(0.0))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A directory of stub programs: grim writes a PPM of the size in its first line of `grim.sizes` per call (the
    /// toplevel capture is tried first), logging its arguments.
    struct Stubs {
        dir: tempfile::TempDir,
    }

    impl Stubs {
        fn new(toplevel: Option<(i64, i64)>, region: Option<(i64, i64)>) -> Self {
            let dir = tempfile::tempdir().unwrap();
            let size = |size: Option<(i64, i64)>| {
                size.map_or(String::from("exit 1"), |(w, h)| {
                    format!("printf 'P6\\n{w} {h}\\n255\\n' > \"$out\"")
                })
            };
            let script = format!(
                "#!/bin/sh\necho \"$@\" >> '{log}'\nfor out; do :; done\ncase \"$*\" in\n*' -T '*) {top} ;;\n*) {region} ;;\nesac\n",
                log = dir.path().join("grim.log").display(),
                top = size(toplevel),
                region = size(region),
            );
            let path = dir.path().join("grim");
            std::fs::write(&path, script).unwrap();
            Self { dir }
        }

        fn tools(&self) -> Tools {
            Tools {
                grim: vec!["sh".into(), self.dir.path().join("grim").into()],
                ..Tools::default()
            }
        }

        fn grim_calls(&self) -> Vec<String> {
            std::fs::read_to_string(self.dir.path().join("grim.log"))
                .unwrap_or_default()
                .lines()
                .map(|line| line.replace(&self.dir.path().to_string_lossy().into_owned(), "<work>"))
                .collect()
        }
    }

    const WINDOW: Geometry = Geometry {
        x: 100,
        y: 50,
        w: 160,
        h: 96,
    };

    fn shot(stubs: &Stubs, stable_id: &str) -> Result<Shot, ClickError> {
        take_shot(&stubs.tools(), stubs.dir.path(), stable_id, WINDOW)
    }

    #[test]
    fn the_toplevel_is_taken_by_stable_id() {
        let stubs = Stubs::new(Some((256, 154)), None);
        let taken = shot(&stubs, "18000004").unwrap();
        assert_eq!((taken.mode, taken.image), (CaptureMode::Toplevel, (256, 154)));
        assert_eq!(stubs.grim_calls(), ["-t ppm -T 18000004 <work>/shot.ppm"]);
    }

    #[test]
    fn no_stable_id_goes_to_the_region_without_trying_t() {
        let stubs = Stubs::new(None, Some((256, 154)));
        let taken = shot(&stubs, "").unwrap();
        assert_eq!(taken.mode, CaptureMode::Region);
        assert_eq!(stubs.grim_calls(), ["-t ppm -g 100,50 160x96 <work>/shot.ppm"]);
    }

    #[test]
    fn a_toplevel_of_the_wrong_shape_falls_back_to_the_region() {
        let stubs = Stubs::new(Some((256, 100)), Some((256, 154)));
        let taken = shot(&stubs, "18000004").unwrap();
        assert_eq!((taken.mode, taken.image), (CaptureMode::Region, (256, 154)));
        assert_eq!(stubs.grim_calls().len(), 2);
    }

    #[test]
    fn a_region_of_the_wrong_shape_is_an_error() {
        let stubs = Stubs::new(Some((256, 100)), Some((256, 100)));
        let error = shot(&stubs, "18000004").err().unwrap();
        assert_eq!(error, ClickError::new("capture does not match the window's shape", 1));
    }

    #[test]
    fn the_scale_tolerance_is_two_percent_of_the_larger() {
        for (height, uniform) in [(154, true), (151, true), (140, false)] {
            assert_eq!(scale_is_uniform((256, height), WINDOW), uniform, "height {height}");
        }
    }

    #[test]
    fn a_failing_region_grim_reports_its_last_line() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("grim");
        std::fs::write(&path, "#!/bin/sh\necho first >&2\necho no compositor >&2\nexit 3\n").unwrap();
        let tools = Tools {
            grim: vec!["sh".into(), path.into()],
            ..Tools::default()
        };
        let error = take_shot(&tools, dir.path(), "", WINDOW).err().unwrap();
        assert_eq!(error, ClickError::new("no compositor", 1));
    }

    #[test]
    fn a_header_that_does_not_parse_is_no_size() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("shot.ppm");
        std::fs::write(&path, "P6\nwide tall\n255\n").unwrap();
        assert_eq!(ppm_size(&path), None);
    }
}
