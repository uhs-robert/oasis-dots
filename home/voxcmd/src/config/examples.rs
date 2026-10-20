//! `integrations examples`: every integration's example phrases, and with `--route` whether each lands on its own
//! integration
//!
//! Routing asks the hooks as `explain` does (a dry run), because a catch-all `{target}` verb only claims a phrase its
//! candidates name: without them every such integration would seem to take every example. The answer can therefore
//! depend on live state (running apps). A phrase with a `<placeholder>` cannot be spoken as written and is skipped, and
//! so is one only said inside a mode that cannot be reproduced: a bash integration's examples when it has a bar surface
//! (said while it is open, and its candidates read the surface), and any example that starts with the wake word (a
//! mode's exit phrase, which routing strips the wake word from).
//!
//! A TOML integration carries its surface and mode as data, so its examples are routed. One that misses as spoken is
//! tried the way the session would hear it: with the surface forced open, and through the mode's declared `rewrite`.
//! Two things cannot be reproduced, and a miss by either is skipped: a `rewrite_hook` (it would run the hook), and the
//! candidates hooks of a surface integration (they read its state file, which stays closed).
use super::Config;
use super::list::relative;
use super::schema::{Candidates, Format};
use crate::exit::CliError;
use crate::hooks::{Dispatch, Hooks, LegacyHooks, NoHooks, ShellHooks};
use crate::route::router::{Router, StepContext};
use crate::session::mode::declared_rewrite;
use crate::text::normalize::normalize;
use regex::Regex;
use serde::Serialize;
use std::sync::LazyLock;

static PLACEHOLDER: LazyLock<Regex> = LazyLock::new(|| Regex::new("<[^>]+>").expect("fixed pattern"));

/// An example with a `<placeholder>` is shown to say, not run.
pub fn has_placeholder(example: &str) -> bool {
    PLACEHOLDER.is_match(example)
}

#[derive(Serialize)]
struct Listed {
    name: String,
    stem: String,
    file: std::path::PathBuf,
    fallback: bool,
    examples: Vec<String>,
}

#[derive(Serialize)]
struct Misrouted {
    integration: String,
    example: String,
    /// The integrations the phrase landed on; none when nothing matched.
    routed_to: Vec<String>,
}

pub fn run(json: bool, route: bool) -> Result<Option<String>, CliError> {
    let dir = crate::paths::config_dir();
    let config = Config::load(&dir).map_err(|message| CliError::usage("integrations examples", message))?;
    if route {
        return route_all(&config, json);
    }
    let listed: Vec<Listed> = config
        .integrations
        .iter()
        .filter(|integration| !integration.examples.is_empty())
        .map(|integration| Listed {
            name: integration.name.clone(),
            stem: integration.stem.clone(),
            file: relative(&dir, &integration.file),
            fallback: integration.tier == super::schema::Tier::Fallback,
            examples: integration.examples.clone(),
        })
        .collect();
    if json {
        return serde_json::to_string(&listed)
            .map(Some)
            .map_err(|error| CliError::failed("integrations examples", error.to_string()));
    }
    let lines: Vec<String> = listed
        .iter()
        .flat_map(|one| {
            std::iter::once(format!("{} ({})", one.name, one.file.display()))
                .chain(one.examples.iter().map(|example| format!("  {example}")))
        })
        .collect();
    Ok(Some(lines.join("\n")))
}

/// Exit 1 when any placeholder-free example does not route to the integration that declares it alone.
fn route_all(config: &Config, json: bool) -> Result<Option<String>, CliError> {
    let hooks: Box<dyn Hooks> = if crate::paths::legacy_dump_override().is_some() {
        // A dump given as a file stands in for bash files that are not on disk to source.
        Box::new(NoHooks)
    } else {
        let dir = crate::paths::config_dir();
        let stems = config.integrations.iter().map(|integration| integration.stem.clone());
        Box::new(Dispatch::new(
            ShellHooks::new(&dir, stems, true),
            Box::new(LegacyHooks::new(dir)),
        ))
    };
    let router = Router::new(config, hooks.as_ref());
    let (mut routed, mut skipped, mut in_mode, mut routed_in_scope) = (0, 0, 0, 0);
    let mut misrouted = Vec::new();
    for (index, integration) in config.integrations.iter().enumerate() {
        for example in &integration.examples {
            if has_placeholder(example) {
                skipped += 1;
                continue;
            }
            let is_toml = integration.format == Format::Toml;
            if (integration.surface.is_some() && !is_toml) || router.wake().split_leading(&normalize(example)).is_some()
            {
                in_mode += 1;
                continue;
            }
            let (mut landed, mut ok) = lands_on(&router, index, example, StepContext::default());
            if !ok && is_toml {
                let has_surface = integration.surface.is_some();
                let rewriting = declared_rewrite(integration, &config.intents)
                    .map_err(|message| CliError::usage("integrations examples", message))?;
                let hook_rewrites = integration
                    .mode
                    .as_ref()
                    .is_some_and(|mode| mode.rewrite_hook.is_some());
                if has_surface || rewriting.is_some() {
                    let in_session_turn = rewriting.is_some();
                    let text = rewriting.map_or_else(|| example.clone(), |one| one.apply(&router.step_text(example)));
                    if text.is_empty() {
                        // Dropped by the mode's `drop`: a way out of the mode, which the session handles itself.
                        in_mode += 1;
                        continue;
                    }
                    let context = StepContext {
                        open_surface: has_surface.then_some(index),
                        // A rewrite happens only to a session turn's words, which get no near-miss pick.
                        in_session_turn,
                        ..StepContext::default()
                    };
                    (landed, ok) = lands_on(&router, index, &text, context);
                    routed_in_scope += usize::from(ok);
                }
                // A forced-open surface is invisible to the hooks, which read the state file themselves, so a miss
                // by an integration whose candidates hooks would read it proves nothing.
                let reads_surface = has_surface
                    && integration
                        .actions
                        .values()
                        .any(|action| matches!(action.candidates, Some(Candidates::Shell(_))));
                if !ok && (hook_rewrites || reads_surface) {
                    in_mode += 1;
                    continue;
                }
            }
            if ok {
                routed += 1;
            } else {
                misrouted.push(Misrouted {
                    integration: integration.name.clone(),
                    example: example.clone(),
                    routed_to: landed,
                });
            }
        }
    }
    let text = if json {
        serde_json::json!({
            "routed": routed,
            "routed_in_scope": routed_in_scope,
            "skipped": skipped,
            "in_mode": in_mode,
            "misrouted": misrouted,
        })
        .to_string()
    } else {
        let mut lines: Vec<String> = misrouted
            .iter()
            .map(|one| {
                let landed = if one.routed_to.is_empty() {
                    "no match".to_string()
                } else {
                    one.routed_to.join(", ")
                };
                format!("{}: \"{}\" routes to {landed}", one.integration, one.example)
            })
            .collect();
        lines.push(format!(
            "{routed} examples route to their integration ({routed_in_scope} only in their surface or mode), {} do not; \
             skipped {skipped} with a <placeholder> and {in_mode} said inside a mode",
            misrouted.len()
        ));
        lines.join("\n")
    };
    if misrouted.is_empty() {
        return Ok(Some(text));
    }
    // The misrouted examples are the output, not an error message: print them, then exit 1 without a stderr line.
    println!("{text}");
    Err(CliError::quiet("integrations examples"))
}

/// The integrations the phrase landed on, and whether it landed on `index` alone.
fn lands_on(router: &Router, index: usize, phrase: &str, context: StepContext) -> (Vec<String>, bool) {
    let (_, options) = router.route_step_with_options(phrase, context);
    let mut landed: Vec<String> = Vec::new();
    for option in &options {
        if !landed.contains(&option.name) {
            landed.push(option.name.clone());
        }
    }
    let ok = !options.is_empty() && options.iter().all(|option| option.integration == index);
    (landed, ok)
}
