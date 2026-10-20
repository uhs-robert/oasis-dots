//! the bash integrations (`integrations.d/*.sh`), read through the bash voxcmd's `_legacy-dump` and mapped onto
//! `Integration` with `Format::Bash`; deleted in 3.2 with the bash voxcmd
//!
//! Sourcing a bash file is the only way to read its settings, so the dump costs one bash start plus a subshell and a
//! `jq` per file. Its output is cached under the cache dir, keyed on every file it depends on (path, mtime, size) and
//! the environment the files read, and rebuilt when any of them changes.
use super::schema::{Action, Candidates, Format, Integration, MatchSettings, Surface, TargetMatch, Tier, Verb, Wait};
use crate::paths;
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};
use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::process::Command;

/// One line of `_legacy-dump` output: what `load_integration` leaves set after sourcing the file.
#[derive(Deserialize)]
struct Dumped {
    file: PathBuf,
    name: String,
    fallback: bool,
    confirm: bool,
    silent: bool,
    target_match: TargetMatch,
    action_labels: bool,
    private_labels: bool,
    verbs: Vec<DumpedVerb>,
    actions: BTreeMap<String, String>,
    no_match_actions: BTreeMap<String, String>,
    step_waits: BTreeMap<String, String>,
    /// The router-called functions the file defines (`candidates`, `surface_open`, ...).
    hooks: Vec<String>,
    /// The file's `pick_command`, empty when it sets none.
    #[serde(default)]
    pick_command: String,
    confirm_labels: Vec<String>,
    match_ignore_words: Vec<String>,
    silent_actions: Vec<String>,
    force_prefixes: Vec<String>,
    mode_actions: Vec<String>,
    /// `mode_actions` plus `mode_entry_actions`.
    mode_switch_actions: Vec<String>,
    free_text_actions: Vec<String>,
    #[serde(default)]
    examples: Vec<String>,
    #[serde(default)]
    help_action: String,
    /// Each `verbs` entry as written; absent from a dump made before `integrations list` needed it.
    #[serde(default)]
    verb_entries: Vec<String>,
}

/// Split as `read -r action pattern` splits a `verbs` entry.
#[derive(Deserialize)]
struct DumpedVerb {
    action: String,
    pattern: String,
}

/// The legacy files of `config_dir/integrations.d`, as `integration_files` globs them: `*.sh`, not hidden, regular
/// files or links to one.
pub fn legacy_files(config_dir: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(config_dir.join("integrations.d")) else {
        return Vec::new();
    };
    let mut files: Vec<PathBuf> = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            let name = path.file_name().unwrap_or_default().to_string_lossy();
            name.ends_with(".sh") && !name.starts_with('.') && path.is_file()
        })
        .collect();
    files.sort();
    files
}

/// Every legacy integration of `config_dir`, from the cache when it is fresh, else from a new dump.
pub fn load(config_dir: &Path) -> Result<Vec<Integration>, String> {
    if let Some(file) = paths::legacy_dump_override() {
        let dump = std::fs::read_to_string(&file).map_err(|error| format!("{}: {error}", file.display()))?;
        return parse_dump(&dump);
    }
    let files = legacy_files(config_dir);
    if files.is_empty() {
        return Ok(Vec::new());
    }
    let bin = paths::legacy_bin();
    let key = cache_key(&bin, &files);
    let cache_file = paths::cache_dir().join(format!(
        "legacy-{:016x}.jsonl",
        fnv1a(config_dir.as_os_str().as_encoded_bytes())
    ));
    if let Ok(cached) = std::fs::read_to_string(&cache_file)
        && let Some(dump) = cached.strip_prefix(&key)
    {
        return parse_dump(dump);
    }
    let dump = run_dump(&bin, config_dir)?;
    let integrations = parse_dump(&dump)?;
    // A cache that cannot be written only costs the next run another dump.
    let _ = write_atomically(&cache_file, &format!("{key}{dump}"));
    Ok(integrations)
}

/// The legacy integrations of just `files`, which may lie outside any config dir, each with `file` set to the path
/// given. `integrations check <file>.sh` loads the file it was asked about and no other.
pub fn load_files(files: &[PathBuf]) -> Result<Vec<Integration>, String> {
    let dump = if let Some(file) = paths::legacy_dump_override() {
        std::fs::read_to_string(&file).map_err(|error| format!("{}: {error}", file.display()))?
    } else {
        // `_legacy-dump` reads a config dir's integrations.d, so the files are linked into a scratch one.
        let scratch = paths::cache_dir().join(format!("check-{}", std::process::id()));
        let staged = scratch.join("integrations.d");
        std::fs::create_dir_all(&staged).map_err(|error| format!("{}: {error}", staged.display()))?;
        let linked = files.iter().try_for_each(|file| {
            let absolute = std::path::absolute(file)?;
            std::os::unix::fs::symlink(&absolute, staged.join(file.file_name().unwrap_or_default()))
        });
        let dumped = linked
            .map_err(|error| format!("{}: {error}", staged.display()))
            .and_then(|()| run_dump(&paths::legacy_bin(), &scratch));
        let _ = std::fs::remove_dir_all(&scratch);
        dumped?
    };
    let mut loaded = parse_dump(&dump)?;
    // The dump names the files by where it saw them; the caller knows them by the path it gave.
    loaded.retain_mut(|integration| {
        let given = files
            .iter()
            .find(|file| file.file_name() == integration.file.file_name());
        if let Some(file) = given {
            integration.file.clone_from(file);
        }
        given.is_some()
    });
    Ok(loaded)
}

fn run_dump(bin: &Path, config_dir: &Path) -> Result<String, String> {
    let output = Command::new(bin)
        .arg("_legacy-dump")
        .env("VOXCMD_CONFIG_DIR", config_dir)
        .output()
        .map_err(|error| format!("{}: {error} (set VOXCMD_LEGACY_BIN to the bash voxcmd)", bin.display()))?;
    if !output.status.success() {
        return Err(format!(
            "{} _legacy-dump failed: {}",
            bin.display(),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    String::from_utf8(output.stdout).map_err(|_| format!("{} _legacy-dump printed non-UTF-8", bin.display()))
}

/// What a dump depends on, as text ending in a blank line: the bash voxcmd and the helpers it and the integrations
/// source (its share dir), each integration file, and the environment that their settings expand at source time.
fn cache_key(bin: &Path, files: &[PathBuf]) -> String {
    let mut depends_on: Vec<PathBuf> = vec![bin.to_path_buf()];
    let real_bin = std::fs::canonicalize(bin).unwrap_or_else(|_| bin.to_path_buf());
    if let Some(bin_dir) = real_bin.parent()
        && let Ok(entries) = std::fs::read_dir(bin_dir.join("../share/voxcmd"))
    {
        let mut helpers: Vec<PathBuf> = entries.filter_map(Result::ok).map(|entry| entry.path()).collect();
        helpers.sort();
        depends_on.extend(helpers);
    }
    depends_on.extend(files.iter().cloned());
    let mut key = String::from("voxcmd legacy dump 1\n");
    for path in depends_on {
        let stamp = std::fs::metadata(&path).ok().map(|meta| {
            let modified = meta
                .modified()
                .ok()
                .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok());
            (modified.map_or(0, |since| since.as_nanos()), meta.len())
        });
        let _ = writeln!(key, "{}\t{stamp:?}", path.display());
    }
    for name in ["HOME", "XDG_CONFIG_HOME", "XDG_RUNTIME_DIR"] {
        let _ = writeln!(key, "{name}={:?}", std::env::var_os(name));
    }
    key.push('\n');
    key
}

/// FNV-1a: a stable name for the config dir's cache file, the same from every build.
fn fnv1a(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf2_9ce4_8422_2325, |hash, &byte| {
        (hash ^ u64::from(byte)).wrapping_mul(0x0100_0000_01b3)
    })
}

fn write_atomically(path: &Path, content: &str) -> std::io::Result<()> {
    let dir = path.parent().unwrap_or(Path::new("."));
    std::fs::create_dir_all(dir)?;
    let temporary = dir.join(format!(
        ".{}.{}",
        path.file_name().unwrap_or_default().to_string_lossy(),
        std::process::id()
    ));
    std::fs::write(&temporary, content)?;
    std::fs::rename(&temporary, path)
}

/// Maps `_legacy-dump` output, one JSON object per line, onto `Integration`s in the dump's order.
pub fn parse_dump(dump: &str) -> Result<Vec<Integration>, String> {
    dump.lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| {
            let dumped: Dumped = serde_json::from_str(line).map_err(|error| format!("_legacy-dump output: {error}"))?;
            let (commands, hooks, pick_command) = (
                dumped.actions.clone(),
                dumped.hooks.clone(),
                dumped.pick_command.clone(),
            );
            let mut integration = integration(dumped);
            crate::click::bridge_map::adapt(&mut integration, &commands, &hooks, &pick_command);
            Ok(integration)
        })
        .collect()
}

fn integration(dumped: Dumped) -> Integration {
    let stem = dumped
        .file
        .file_stem()
        .unwrap_or_default()
        .to_string_lossy()
        .into_owned();
    let listed = |list: &[String]| list.iter().cloned().collect::<BTreeSet<String>>();
    let (silent_actions, free_text, mode, mode_switch) = (
        listed(&dumped.silent_actions),
        listed(&dumped.free_text_actions),
        listed(&dumped.mode_actions),
        listed(&dumped.mode_switch_actions),
    );
    let has_candidates = dumped.hooks.iter().any(|hook| hook == "candidates");
    let actions = dumped
        .actions
        .iter()
        .map(|(id, run)| {
            let action = Action {
                run: run.clone(),
                candidates: has_candidates.then_some(Candidates::LegacyFunction),
                no_match: dumped.no_match_actions.get(id).cloned(),
                silent: dumped.silent || silent_actions.contains(id),
                free_text: free_text.contains(id),
                mode_switch: mode.contains(id),
                mode_entry: mode_switch.contains(id) && !mode.contains(id),
                wait: dumped.step_waits.get(id).cloned().map(Wait::LegacyCondition),
                timeout_secs: None,
                ..Action::default()
            };
            (id.clone(), action)
        })
        .collect();
    Integration {
        name: dumped.name,
        stem,
        file: dumped.file,
        format: Format::Bash,
        tier: if dumped.fallback { Tier::Fallback } else { Tier::Normal },
        force_prefixes: dumped.force_prefixes,
        defines: BTreeMap::new(),
        mode_exit_object: None,
        mode: None,
        verbs: dumped
            .verbs
            .into_iter()
            .enumerate()
            .map(|(index, verb)| Verb {
                action: verb.action,
                pattern: verb.pattern,
                line: None,
                column: None,
                requires: None,
                listed: dumped.verb_entries.get(index).cloned(),
            })
            .collect(),
        examples: dumped.examples,
        legacy_help: lists_help(&dumped.hooks, &dumped.help_action),
        help: Vec::new(),
        settings: MatchSettings {
            target_match: dumped.target_match,
            match_ignore_words: dumped.match_ignore_words,
            confirm: dumped.confirm,
            confirm_labels: dumped.confirm_labels,
            private_labels: dumped.private_labels,
            action_labels: dumped.action_labels,
        },
        actions,
        surface: dumped
            .hooks
            .iter()
            .any(|hook| hook == "surface_open")
            .then_some(Surface::LegacyHook),
        picker: None,
    }
}

/// As `help_listed` in the bash voxcmd decides: `help_choices`, else `candidates` run for a `help_action`.
fn lists_help(hooks: &[String], help_action: &str) -> bool {
    let defines = |hook: &str| hooks.iter().any(|defined| defined == hook);
    defines("help_choices") || (!help_action.is_empty() && defines("candidates"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_committed_dump_maps_onto_integrations() {
        let dump = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/legacy-dump.jsonl"))
            .expect("run gen-match-goldens.sh");
        let integrations = parse_dump(&dump).unwrap();
        let keybinds = integrations.iter().find(|i| i.stem == "keybinds").unwrap();
        assert_eq!(keybinds.tier, Tier::Fallback);
        assert_eq!(keybinds.force_prefixes, ["keybind", "key bind"]);
        assert!(matches!(
            keybinds.actions.values().next().unwrap().candidates,
            Some(Candidates::LegacyFunction)
        ));
        let overview = integrations.iter().find(|i| i.stem == "overview").unwrap();
        assert!(matches!(overview.surface, Some(Surface::LegacyHook)));
        let media = integrations.iter().find(|i| i.stem == "media").unwrap();
        assert_eq!(media.verbs[0].action, "toggle");
        assert!(media.actions["volume_up"].silent);
        assert_eq!(media.examples[0], "play pause");
        let rapid = integrations.iter().find(|i| i.stem == "rapid").unwrap();
        assert!(rapid.actions["rapid_mode"].mode_switch);
    }

    #[test]
    fn a_verb_keeps_its_entry_as_written_for_list() {
        let dump = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/legacy-dump.jsonl"))
            .expect("run gen-match-goldens.sh");
        let first = dump.lines().next().unwrap().trim_end_matches('}').to_string();
        let entries = format!("{first},\"verb_entries\":[\"time    aligned\"]}}");
        assert_eq!(
            parse_dump(&entries).unwrap()[0].verbs[0].listed.as_deref(),
            Some("time    aligned")
        );
    }

    #[test]
    fn the_cache_key_changes_with_a_file() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("a.sh");
        std::fs::write(&file, "verbs=()").unwrap();
        let before = cache_key(Path::new("/nonexistent/voxcmd"), std::slice::from_ref(&file));
        std::fs::write(&file, "verbs=(x)").unwrap();
        assert_ne!(before, cache_key(Path::new("/nonexistent/voxcmd"), &[file]));
    }
}
