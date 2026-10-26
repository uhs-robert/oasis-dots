//! loads ~/.config/voxcmd: integrations/*.toml, replacements.d/*, intents.local, and the voice settings voxcmd shares
//! with the bar
pub mod check;
pub mod examples;
pub mod intents;
pub mod list;
pub mod schema;
pub mod voice_env;

use crate::text::normalize::Replacements;
use intents::Intents;
use schema::Integration;
use std::path::Path;

pub struct Config {
    /// In bytewise file-name order, which is routing order: tiers are filters over this list, never re-sorted.
    pub integrations: Vec<Integration>,
    pub intents: Intents,
    pub replacements: Replacements,
}

impl Config {
    /// Every integration of `dir`.
    pub fn load(dir: &Path) -> Result<Self, String> {
        let intents = Intents::load(dir);
        let mut integrations = Vec::new();
        for file in toml_files(dir) {
            let integration = schema::load_toml(&file)?;
            crate::route::pattern::compile_mode(&integration, &intents)?;
            integrations.push(integration);
        }
        integrations.sort_by(|a, b| a.file.file_name().cmp(&b.file.file_name()));
        Ok(Self {
            integrations,
            intents,
            replacements: Replacements::load(&dir.join("replacements.d")),
        })
    }
}

/// The stems of the integrations `Config::load` takes from `dir`, in its order, found by file name alone: a hook's
/// `VOXCMD_INTEGRATIONS` where no `Config` is loaded (a session's mode hooks, which run under the session lock).
pub fn integration_stems(dir: &Path) -> Vec<String> {
    toml_files(dir)
        .iter()
        .map(|file| file.file_stem().unwrap_or_default().to_string_lossy().into_owned())
        .collect()
}

fn toml_files(dir: &Path) -> Vec<std::path::PathBuf> {
    let Ok(entries) = std::fs::read_dir(dir.join("integrations")) else {
        return Vec::new();
    };
    let mut files: Vec<_> = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            let name = path.file_name().unwrap_or_default().to_string_lossy();
            name.ends_with(".toml") && !name.starts_with('.') && path.is_file()
        })
        .collect();
    files.sort();
    files
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_leftover_bash_file_is_not_read() {
        let dir = tempfile::tempdir().unwrap();
        let fixtures = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
        std::fs::create_dir_all(dir.path().join("integrations")).unwrap();
        std::fs::create_dir_all(dir.path().join("integrations.d")).unwrap();
        std::fs::copy(
            fixtures.join("integrations/media.toml"),
            dir.path().join("integrations/media.toml"),
        )
        .unwrap();
        std::fs::write(dir.path().join("integrations.d/other.sh"), "exit 1").unwrap();
        let config = Config::load(dir.path()).unwrap();
        assert_eq!(config.integrations.len(), 1);
        assert_eq!(integration_stems(dir.path()), ["media"]);
    }
}
