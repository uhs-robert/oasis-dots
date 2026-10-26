//! `help` (Voice Help): every integration's example phrases in the picker, grouped with the fallbacks last (was
//! `voice_help` and `help_group`)
//!
//! A phrase without placeholders runs as if spoken; one with a `<placeholder>` cannot be completed from a click, so it
//! is shown as a toast to say instead. Tab on an integration that lists help choices shows them, and picking one runs
//! it as a spoken match would. Picked ids are `say:<phrase>` or `run:<index into every group's runnables>`.
use crate::actions::Spoken;
use crate::ask::AskWith;
use crate::config::examples::has_placeholder;
use crate::notify::Kind;
use crate::route::resolve::{PendingMatch, RouteOption, runnable};
use crate::route::runner::Runner;
use serde_json::{Map, Value, json};

struct Group {
    key: String,
    name: String,
    fallback: bool,
    examples: Vec<String>,
    runnables: Vec<RouteOption>,
}

/// The exit code `help` ends with: 0 when the user decided (including a cancel), else the routed phrase's or the run
/// option's, and 1 when no integration declares examples.
pub fn run(runner: &Runner) -> i32 {
    let groups = groups(runner);
    if groups.iter().all(|group| group.examples.is_empty()) {
        runner
            .rt
            .notifier
            .notify(Kind::Info, "voxcmd", "No integration declares examples");
        return 1;
    }
    let runnables: Vec<&RouteOption> = groups.iter().flat_map(|group| &group.runnables).collect();
    let choices: Vec<Value> = groups
        .iter()
        .flat_map(|group| {
            group.examples.iter().map(move |example| {
                let mut choice = json!({"id": format!("say:{example}"), "label": format!("{}: {example}", group.name)});
                if !group.runnables.is_empty() {
                    choice["expand"] = json!(group.key);
                }
                choice
            })
        })
        .collect();
    // A run: id indexes `runnables`, so each group's ids start past the ones before.
    let mut expansions = Map::new();
    let mut first_index = 0;
    for group in &groups {
        if !group.runnables.is_empty() {
            let listed: Vec<Value> = group
                .runnables
                .iter()
                .enumerate()
                .map(|(offset, option)| json!({"id": format!("run:{}", first_index + offset), "label": option.label}))
                .collect();
            expansions.insert(group.key.clone(), json!({"title": group.name, "choices": listed}));
        }
        first_index += group.runnables.len();
    }
    let picked = AskWith::from_env().pick_id(
        "Voice Help",
        &Value::Array(choices).to_string(),
        &Value::Object(expansions).to_string(),
    );
    let Some(picked) = picked else { return 0 };
    if let Some(index) = picked.strip_prefix("run:") {
        let Some(option) = index.parse::<usize>().ok().and_then(|index| runnables.get(index)) else {
            return 0;
        };
        let said = Spoken {
            phrase: "",
            raw_transcript: "",
            active_before: "",
            in_sequence: false,
        };
        return runner.run_option(option, &said).exit_code;
    }
    let phrase = picked.strip_prefix("say:").unwrap_or(&picked);
    if has_placeholder(phrase) {
        runner
            .rt
            .notifier
            .notify(Kind::Info, "voxcmd", &format!("Say: {}", markup_escape(phrase)));
        0
    } else {
        runner.route(phrase).exit_code
    }
}

/// Integrations that have something to show, in routing order with the fallbacks last.
fn groups(runner: &Runner) -> Vec<Group> {
    let config = runner.rt.config;
    let shell = runner.rt.shell;
    // One bash start per file that lists choices (its `[[help]]` hooks); they run side by side.
    let entries: Vec<_> = std::thread::scope(|scope| {
        let running: Vec<_> = config
            .integrations
            .iter()
            .map(|integration| scope.spawn(move || shell.help_entries(integration)))
            .collect();
        running
            .into_iter()
            .map(|handle| handle.join().expect("a help thread panicked"))
            .collect()
    });
    let mut groups: Vec<Group> = config
        .integrations
        .iter()
        .enumerate()
        .zip(entries)
        .map(|((index, integration), entries)| {
            let count = entries.len();
            let runnables = entries
                .into_iter()
                .map(|(action, candidate)| {
                    let pending = PendingMatch {
                        integration: index,
                        verb_action: action.clone(),
                        // What saying the entry would have captured, for actions that read it.
                        target: candidate.label.clone(),
                        has_target: true,
                        args: Vec::new(),
                        near_miss: None,
                    };
                    runnable(integration, &pending, &action, count, candidate)
                })
                .collect();
            Group {
                key: integration.stem.clone(),
                name: integration.name.clone(),
                fallback: integration.tier == crate::config::schema::Tier::Fallback,
                examples: integration.examples.clone(),
                runnables,
            }
        })
        .filter(|group| !group.examples.is_empty() || !group.runnables.is_empty())
        .collect();
    groups.sort_by_key(|group| group.fallback);
    groups
}

/// Toast bodies are markup, which would swallow a placeholder as a tag.
fn markup_escape(text: &str) -> String {
    text.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

#[cfg(test)]
mod tests {
    use super::markup_escape;

    #[test]
    fn a_placeholder_survives_markup() {
        assert_eq!(markup_escape("volume <n> & up"), "volume &lt;n&gt; &amp; up");
    }
}
