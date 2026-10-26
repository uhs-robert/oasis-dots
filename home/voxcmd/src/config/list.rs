//! `integrations list`: every integration and its verbs, in routing order
use super::Config;
use super::schema::{Integration, Surface};
use crate::exit::CliError;
use crate::route::pattern;
use serde::Serialize;
use std::path::{Path, PathBuf};

#[derive(Serialize)]
struct IntegrationSummary {
    name: String,
    stem: String,
    file: PathBuf,
    hook_file: Option<PathBuf>,
    fallback: bool,
    force_prefixes: Vec<String>,
    surface: Option<String>,
    mode: Option<String>,
    verbs: Vec<VerbRef>,
    actions: Vec<String>,
}

#[derive(Serialize)]
struct VerbRef {
    index: usize,
    line: Option<usize>,
    action: String,
    pattern: String,
    /// Empty when the pattern does not compile; `integrations check` says why.
    regex: String,
}

pub fn run(json: bool) -> Result<Option<String>, CliError> {
    let dir = crate::paths::config_dir();
    let config = Config::load(&dir).map_err(|message| CliError::usage("integrations list", message))?;
    if json {
        let summaries: Vec<IntegrationSummary> = config
            .integrations
            .iter()
            .map(|integration| summary(&dir, integration, &config))
            .collect();
        let text = serde_json::to_string(&summaries)
            .map_err(|error| CliError::failed("integrations list", error.to_string()))?;
        return Ok(Some(text));
    }
    Ok(Some(text(&config.integrations)))
}

/// One line per integration, then one per verb; a file with no verbs gets a blank verb line.
fn text(integrations: &[Integration]) -> String {
    let mut lines = Vec::new();
    for integration in integrations {
        let fallback = if integration.tier == super::schema::Tier::Fallback {
            " [fallback]"
        } else {
            ""
        };
        lines.push(format!(
            "{} ({}){fallback}",
            integration.name,
            integration.file.display()
        ));
        if integration.verbs.is_empty() {
            lines.push("  ".to_string());
        }
        lines.extend(
            integration
                .verbs
                .iter()
                .map(|verb| format!("  {} {}", verb.action, verb.pattern)),
        );
    }
    lines.join("\n")
}

fn summary(dir: &Path, integration: &Integration, config: &Config) -> IntegrationSummary {
    let hook_file = integration.file.with_extension("sh");
    IntegrationSummary {
        name: integration.name.clone(),
        stem: integration.stem.clone(),
        file: relative(dir, &integration.file),
        hook_file: hook_file.is_file().then(|| relative(dir, &hook_file)),
        fallback: integration.tier == super::schema::Tier::Fallback,
        force_prefixes: integration.force_prefixes.clone(),
        surface: integration.surface.as_ref().map(|surface| match surface {
            Surface::StateFile(path) => path.display().to_string(),
        }),
        mode: integration.mode.as_ref().map(|mode| mode.label.clone()),
        verbs: integration
            .verbs
            .iter()
            .enumerate()
            .map(|(index, verb)| VerbRef {
                index,
                line: verb.line,
                action: verb.action.clone(),
                pattern: verb.pattern.clone(),
                regex: pattern::compile(integration, verb, &config.intents)
                    .map(|compiled| compiled.regex)
                    .unwrap_or_default(),
            })
            .collect(),
        actions: integration.actions.keys().cloned().collect(),
    }
}

/// The path as the config dir names it (`integrations/media.toml`), or whole when it lies elsewhere.
pub fn relative(dir: &Path, file: &Path) -> PathBuf {
    file.strip_prefix(dir).unwrap_or(file).to_path_buf()
}
