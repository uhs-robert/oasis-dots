//! loads ~/.config/voxcmd: integrations/*.toml and the legacy integrations.d/*.sh, replacements.d/*, intents.local,
//! and the voice settings voxcmd shares with the bar
pub mod intents;
pub mod legacy;
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
    /// Every integration of `dir`. A stem with both an `integrations/<stem>.toml` and an `integrations.d/<stem>.sh`
    /// is the TOML one, so a converted file can sit beside its bash original until 3.2 deletes `integrations.d/`.
    pub fn load(dir: &Path) -> Result<Self, String> {
        let intents = Intents::load(dir);
        let mut integrations = Vec::new();
        for file in toml_files(dir) {
            let integration = schema::load_toml(&file)?;
            crate::route::pattern::compile_mode(&integration, &intents)?;
            integrations.push(integration);
        }
        let converted: Vec<String> = integrations
            .iter()
            .map(|integration| integration.stem.clone())
            .collect();
        // A dump given as a file (tests, benchmarks) stands in for the bash files, so it needs none to be on disk.
        if crate::paths::legacy_dump_override().is_some()
            || legacy::legacy_files(dir)
                .iter()
                .any(|file| !converted.iter().any(|stem| file.file_stem() == Some(stem.as_ref())))
        {
            let legacy = legacy::load(dir)?;
            integrations.extend(
                legacy
                    .into_iter()
                    .filter(|integration| !converted.contains(&integration.stem)),
            );
        }
        integrations.sort_by(|a, b| a.file.file_name().cmp(&b.file.file_name()));
        Ok(Self {
            integrations,
            intents,
            replacements: Replacements::load(&dir.join("replacements.d")),
        })
    }
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
    fn toml_wins_over_the_bash_file_of_the_same_stem() {
        let dir = tempfile::tempdir().unwrap();
        let fixtures = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
        std::fs::create_dir_all(dir.path().join("integrations")).unwrap();
        std::fs::create_dir_all(dir.path().join("integrations.d")).unwrap();
        std::fs::copy(
            fixtures.join("integrations/media.toml"),
            dir.path().join("integrations/media.toml"),
        )
        .unwrap();
        // The bash file is never sourced: its stem has a TOML file, and no other legacy file needs a dump.
        std::fs::write(dir.path().join("integrations.d/media.sh"), "exit 1").unwrap();
        let config = Config::load(dir.path()).unwrap();
        assert_eq!(config.integrations.len(), 1);
        assert_eq!(config.integrations[0].format, schema::Format::Toml);
    }
}
