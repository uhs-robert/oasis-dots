//! the three model files and the first-use download of the two that are not tracked
//!
//! The head (`cortana.onnx`) is trained for this repo and tracked in voxcmd's share folder. The mel and embedding models
//! every openWakeWord model runs on are not packaged: they download from the v0.5.1 release into the cache. Every file
//! is checked against a sha256 pin, so a changed download is refused and a changed file in place is not used.
//!
//! Self-contained so `tests/wake_models.rs` includes it by path.
use sha2::{Digest, Sha256};
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};

pub const WAKE_MODEL: &str = "cortana.onnx";
pub const WAKE_MODEL_SHA256: &str = "4c8ef56a302ed1b2863dabeaf5c84bb473dcdaf3a9ae65191608bf17ac8b1fe9";
pub const RELEASE_URL: &str = "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/";
pub const FEATURE_MODELS: [(&str, &str); 2] = [
    (
        "melspectrogram.onnx",
        "ba2b0e0f8b7b875369a2c89cb13360ff53bac436f2895cced9f479fa65eb176f",
    ),
    (
        "embedding_model.onnx",
        "70d164290c1d095d1d4ee149bc5e00543250a7316b59f31d056cff7bd3075c1f",
    ),
];

/// curl's cap on one download, whose files are 1 MB. A stalled connection must not hold the unit's start for the
/// `TimeoutStartSec` of five minutes.
const DOWNLOAD_LIMIT_SECS: &str = "120";

pub fn file_sha256(path: &Path) -> std::io::Result<String> {
    let mut file = std::fs::File::open(path)?;
    let mut digest = Sha256::new();
    let mut block = vec![0u8; 1 << 16];
    loop {
        let read = file.read(&mut block)?;
        if read == 0 {
            break;
        }
        digest.update(&block[..read]);
    }
    Ok(format!("{:x}", digest.finalize()))
}

/// What stops the listener from starting, as a sentence, or None.
pub fn missing_setup(model_dir: &Path, wake_model: &Path, features: &[(&str, &str)]) -> Option<String> {
    let where_is = wake_model.parent().unwrap_or(wake_model).display();
    if !wake_model.exists() {
        return Some(format!("{WAKE_MODEL} is not in {where_is}"));
    }
    if file_sha256(wake_model).ok().as_deref() != Some(WAKE_MODEL_SHA256) {
        return Some(format!("{WAKE_MODEL} in {where_is} is not the tracked model"));
    }
    for (name, pin) in features {
        let path = model_dir.join(name);
        if !path.exists() {
            return Some(format!("{name} is not in {}", model_dir.display()));
        }
        if file_sha256(&path).ok().as_deref() != Some(pin) {
            return Some(format!(
                "{name} in {} is not the pinned release file",
                model_dir.display()
            ));
        }
    }
    None
}

/// Makes every feature model present and pinned. A file in place that differs is deleted and fetched again, and a
/// download that differs is deleted and refused. `say` gets a line for each step, for a toast.
pub fn fetch(
    model_dir: &Path,
    base_url: &str,
    features: &[(&str, &str)],
    say: &mut dyn FnMut(&str),
) -> Result<(), String> {
    std::fs::create_dir_all(model_dir).map_err(|error| format!("{}: {error}", model_dir.display()))?;
    for (name, pin) in features {
        let target = model_dir.join(name);
        if target.exists() {
            if file_sha256(&target).ok().as_deref() == Some(pin) {
                continue;
            }
            say(&format!("{name} does not match the release, fetching it again"));
            std::fs::remove_file(&target).map_err(|error| format!("{}: {error}", target.display()))?;
        }
        say(&format!("Downloading {name}"));
        let partial = model_dir.join(format!("{name}.part"));
        let url = format!("{base_url}{name}");
        let status = Command::new("curl")
            .args([
                "--fail",
                "--silent",
                "--show-error",
                "--location",
                "--max-time",
                DOWNLOAD_LIMIT_SECS,
                "--output",
            ])
            .arg(&partial)
            .arg(&url)
            .stdin(Stdio::null())
            .status()
            .map_err(|error| format!("cannot run curl: {error}"))?;
        if !status.success() {
            let _ = std::fs::remove_file(&partial);
            return Err(format!("{url}: curl failed ({status})"));
        }
        let got = file_sha256(&partial).map_err(|error| format!("{}: {error}", partial.display()))?;
        if got != *pin {
            let _ = std::fs::remove_file(&partial);
            return Err(format!("{name} downloaded with sha256 {got}, expected {pin}"));
        }
        std::fs::rename(&partial, &target).map_err(|error| format!("{}: {error}", target.display()))?;
    }
    Ok(())
}
