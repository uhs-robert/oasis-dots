//! `voxcmd ask pick [--listen] <label> <choices-json> [<expansions-json>]`: the text picker (was `voxcmd-pick`)
//!
//! Choices are a JSON array of strings or `{id, label, expand}` objects; prints the picked id (the string itself for a
//! plain string) and exits 0, or exits 1 on cancel. Uses the bar's "choices" picker through `qs-picker`, which falls
//! back to rofi. Expansions are `{key: {title, choices}}`: Tab on a choice whose `expand` names a key shows that list,
//! Backspace on an empty search comes back; rofi shows only the top level.
use super::{
    Asking, Expansion, Owner, PendingPick, PickChoice, StopSignals, Stopped, is_executable, qs_ipc_call, shell_quote,
    terminate_with_children,
};
use crate::exit::CliError;
use crate::paths;
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::process::{Command, Stdio};

/// What the bar's picker reads from `spec.json`. With no id it only writes the pick to `result_path` and skips the
/// Hyprland prompt callback.
#[derive(Serialize)]
struct ChoicesSpec<'a> {
    label: &'a str,
    result_path: &'a PathBuf,
    view_path: &'a PathBuf,
    choices: Vec<SpecChoice<'a>>,
    expansions: BTreeMap<&'a str, SpecExpansion<'a>>,
}

#[derive(Serialize)]
#[serde(untagged)]
enum SpecChoice<'a> {
    Label(&'a str),
    Expandable { label: &'a str, expand: &'a str },
}

#[derive(Serialize)]
struct SpecExpansion<'a> {
    title: &'a str,
    choices: Vec<&'a str>,
}

/// The choices as the picker shows them. Both pickers hand back the picked label, not its position, so numbering makes
/// every label unique and gives a voice reply an ordinal to say; a label several choices share also gets its id, so
/// the user can tell them apart. A tab would split the `<key><TAB><label>` an expanded pick comes back as.
pub fn normalize_choices(list: &Value) -> Result<Vec<PickChoice>, String> {
    let Value::Array(items) = list else {
        return Err("choices must be a JSON array".to_string());
    };
    let mut choices = Vec::new();
    for item in items {
        let choice = match item {
            Value::String(text) => PickChoice {
                id: text.clone(),
                label: text.clone(),
                expand: None,
                r#box: None,
            },
            Value::Object(_) | Value::Null => PickChoice {
                id: jq_text(&item["id"]),
                label: jq_text(jq_or(&item["label"], &item["id"])),
                expand: jq_truthy(&item["expand"]).then(|| jq_text(&item["expand"])),
                r#box: None,
            },
            other => return Err(format!("a choice is neither a string nor an object: {other}")),
        };
        choices.push(PickChoice {
            label: choice.label.replace('\t', " "),
            ..choice
        });
    }
    let shared: Vec<String> = choices
        .iter()
        .filter(|choice| choices.iter().filter(|other| other.label == choice.label).count() > 1)
        .map(|choice| choice.label.clone())
        .collect();
    for (index, choice) in choices.iter_mut().enumerate() {
        if shared.contains(&choice.label) {
            choice.label = format!("{} ({})", choice.label, choice.id);
        }
        choice.label = format!("{}. {}", index + 1, choice.label);
    }
    Ok(choices)
}

/// The expansions as the picker shows them: a key holding a tab is dropped (it would split the answer), and so is an
/// expansion with no choices.
pub fn normalize_expansions(map: &Value) -> Result<BTreeMap<String, Expansion>, String> {
    let Value::Object(entries) = map else {
        return Err("expansions must be a JSON object".to_string());
    };
    let mut expansions = BTreeMap::new();
    for (key, value) in entries {
        if key.contains('\t') {
            continue;
        }
        if !matches!(value, Value::Object(_) | Value::Null) {
            return Err(format!("expansion {key:?} is not an object"));
        }
        let choices = match &value["choices"] {
            Value::Null | Value::Bool(false) => Vec::new(),
            list => normalize_choices(list)?,
        };
        if !choices.is_empty() {
            let title = match &value["title"] {
                Value::Null | Value::Bool(false) => String::new(),
                title => jq_text(title),
            };
            expansions.insert(key.clone(), Expansion { title, choices });
        }
    }
    Ok(expansions)
}

/// jq's `tostring`: a string as itself, anything else as its JSON text.
fn jq_text(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        other => other.to_string(),
    }
}

/// jq's truthiness: everything but null and false.
fn jq_truthy(value: &Value) -> bool {
    !matches!(value, Value::Null | Value::Bool(false))
}

/// jq's `a // b`.
fn jq_or<'a>(a: &'a Value, b: &'a Value) -> &'a Value {
    if jq_truthy(a) { a } else { b }
}

/// The choices and expansions to ask with, from the command line's JSON. Empty expansions are none, as the bash
/// `${3:-"{}"}` read them.
pub fn prepare(
    choices_json: &str,
    expansions_json: &str,
) -> Result<(Vec<PickChoice>, BTreeMap<String, Expansion>), String> {
    let parse = |json: &str| serde_json::from_str::<Value>(json).map_err(|error| format!("not JSON: {error}"));
    let mut choices = normalize_choices(&parse(choices_json)?)?;
    let expansions_json = if expansions_json.is_empty() {
        "{}"
    } else {
        expansions_json
    };
    let expansions = normalize_expansions(&parse(expansions_json)?)?;
    for choice in &mut choices {
        if choice.expand.as_ref().is_some_and(|key| !expansions.contains_key(key)) {
            choice.expand = None;
        }
    }
    Ok((choices, expansions))
}

/// The id of the choice whose label came back: from the top level, or from the expansion an answer
/// `<key><TAB><label>` names.
pub fn picked_id(picked: &str, choices: &[PickChoice], expansions: &BTreeMap<String, Expansion>) -> Option<String> {
    let (key, label) = picked.split_once('\t').unwrap_or(("", picked));
    let list = if key.is_empty() {
        choices
    } else {
        expansions.get(key).map_or(&[][..], |expansion| &expansion.choices)
    };
    let id = &list.iter().find(|choice| choice.label == label)?.id;
    (!id.is_empty()).then(|| id.clone())
}

/// `voxcmd ask pick`.
pub fn run(
    listen: bool,
    label: &str,
    choices_json: &str,
    expansions_json: Option<&str>,
) -> Result<Option<String>, CliError> {
    let signals = StopSignals::hold();
    let (choices, expansions) = prepare(choices_json, expansions_json.unwrap_or_default())
        .map_err(|message| CliError::usage("ask pick", message))?;
    let mut asking = Asking::create("pick")?;
    let picked = ask(&mut asking, &signals, listen, label, &choices, &expansions);
    let Ok(picked) = picked else {
        return Err(CliError::quiet("ask pick"));
    };
    picked_id(&picked?, &choices, &expansions)
        .map(Some)
        .ok_or_else(|| CliError::quiet("ask pick"))
}

/// The answer line, or none when the pick was cancelled or timed out.
fn ask(
    asking: &mut Asking,
    signals: &StopSignals,
    listen: bool,
    label: &str,
    choices: &[PickChoice],
    expansions: &BTreeMap<String, Expansion>,
) -> Result<Result<String, CliError>, Stopped> {
    // The expansion key the picker shows, empty for the top level, so a voice reply answers from what is on screen.
    let view_path = asking.dir.join("view");
    let labels_path = asking.dir.join("labels");
    let spec_path = asking.dir.join("spec.json");
    let picker_files = (|| {
        std::fs::write(&view_path, "")?;
        let labels: String = choices.iter().map(|choice| format!("{}\n", choice.label)).collect();
        std::fs::write(&labels_path, labels)?;
        let spec = ChoicesSpec {
            label,
            result_path: &asking.fifo,
            view_path: &view_path,
            choices: choices
                .iter()
                .map(|choice| match &choice.expand {
                    Some(expand) => SpecChoice::Expandable {
                        label: &choice.label,
                        expand,
                    },
                    None => SpecChoice::Label(&choice.label),
                })
                .collect(),
            expansions: expansions
                .iter()
                .map(|(key, expansion)| {
                    let shown = SpecExpansion {
                        title: &expansion.title,
                        choices: expansion.choices.iter().map(|choice| choice.label.as_str()).collect(),
                    };
                    (key.as_str(), shown)
                })
                .collect(),
        };
        std::fs::write(
            &spec_path,
            serde_json::to_string(&spec).expect("the spec serializes") + "\n",
        )
    })();
    if let Err(error) = picker_files {
        return Ok(Err(CliError::failed("ask pick", error.to_string())));
    }
    if let Err(error) = asking.publish(&PendingPick {
        pid: std::process::id(),
        owner: Owner::Ask,
        fifo: Some(asking.fifo.clone()),
        token: None,
        label: label.to_string(),
        kind: None,
        choices: choices.to_vec(),
        expansions: expansions.clone(),
        view: Some(view_path),
        listen_again: None,
        verb: None,
        view_key: None,
    }) {
        return Ok(Err(error));
    }
    // A signal during setup ends the ask before the question shows, as the bash trap did.
    signals.check()?;
    if listen {
        asking.start_reply_recording(signals)?;
    }
    // Opening the FIFO for writing happens before rofi runs, so even a missing rofi closes it and reads as a cancel.
    let rofi_fallback = format!(
        "rofi -dmenu -i -p {} < {} > {}",
        shell_quote(label.as_ref()),
        shell_quote(labels_path.as_os_str()),
        shell_quote(asking.fifo.as_os_str())
    );
    let qs_picker = paths::hypr_script("qs-picker");
    let uses_qs_picker = is_executable(&qs_picker);
    let mut picker = if uses_qs_picker {
        let mut command = Command::new(qs_picker);
        command.arg("choices").arg(&rofi_fallback).arg(&spec_path);
        command
    } else {
        let mut command = Command::new("sh");
        command.args(["-c", &rofi_fallback]);
        command
    };
    let mut picker = picker.stdin(Stdio::null()).spawn().ok();
    signals.check()?;
    // A pick timeout, so a bar that dies mid-pick cannot leave callers blocked forever.
    let timeout = super::timeout_setting("VOXCMD_PICK_TIMEOUT", "300");
    let picked = asking.read_answer(&timeout, signals)?;
    // Read before clean_up removes our own entry: a pending pick that is not ours is a newer ask, whose picker a close would dismiss.
    let newer_ask_pending = !asking.owns_pending_pick() && paths::pending_pick().exists();
    // Removed before closing: closing the bar's picker writes a cancel to the FIFO, which must find it gone.
    asking.clean_up();
    // qs-picker exits when the bar takes the pick but can lag the answer, so whether it has exited cannot tell the bar's
    // picker from rofi: a qs-picker is always closed through the bar (a no-op when it fell back to rofi), and whatever is
    // still running is terminated.
    let picker_running = picker
        .as_mut()
        .is_some_and(|picker| picker.try_wait().is_ok_and(|status| status.is_none()));
    if let Some(picker) = picker.filter(|_| picker_running) {
        terminate_with_children(&picker);
    }
    if (uses_qs_picker || !picker_running) && !newer_ask_pending && is_executable(&paths::qs_ipc()) {
        // A no-op unless a voice reply or the timeout ended the pick while the picker was still open.
        qs_ipc_call(&["picker".as_ref(), "close".as_ref()]);
    }
    Ok(if picked.is_empty() {
        Err(CliError::quiet("ask pick"))
    } else {
        Ok(picked)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn labels(choices: &[PickChoice]) -> Vec<&str> {
        choices.iter().map(|choice| choice.label.as_str()).collect()
    }

    #[test]
    fn choices_are_numbered_and_a_shared_label_gets_its_id() {
        let choices = normalize_choices(&json!([
            "Firefox",
            {"id": 7, "label": "Slack"},
            {"id": "b", "label": "Slack"},
            {"id": "t", "label": "a\tb"},
            {"id": "x"},
            {"id": "f", "label": false}
        ]))
        .unwrap();
        assert_eq!(
            labels(&choices),
            ["1. Firefox", "2. Slack (7)", "3. Slack (b)", "4. a b", "5. x", "6. f"]
        );
        assert_eq!(choices[0].id, "Firefox");
        assert_eq!(choices[1].id, "7");
        assert!(normalize_choices(&json!([3])).is_err());
    }

    #[test]
    fn an_expand_naming_no_expansion_is_dropped_and_so_is_an_empty_expansion() {
        let (choices, expansions) = prepare(
            r#"[{"id":"a","label":"A","expand":"more"},{"id":"b","label":"B","expand":"none"},{"id":"c","label":"C","expand":"empty"}]"#,
            r#"{"more":{"title":"More","choices":["x","y"]},"empty":{"title":"E","choices":[]},"a\tb":{"choices":["z"]},
                "off":{"choices":false}}"#,
        )
        .unwrap();
        assert_eq!(choices[0].expand.as_deref(), Some("more"));
        assert_eq!(choices[1].expand, None);
        assert_eq!(choices[2].expand, None);
        assert_eq!(expansions.keys().collect::<Vec<_>>(), ["more"]);
        assert_eq!(labels(&expansions["more"].choices), ["1. x", "2. y"]);
    }

    #[test]
    fn empty_expansions_are_none() {
        let (choices, expansions) = prepare(r#"["a"]"#, "").unwrap();
        assert_eq!(labels(&choices), ["1. a"]);
        assert!(expansions.is_empty());
    }

    #[test]
    fn the_answer_maps_back_to_an_id() {
        let (choices, expansions) = prepare(
            r#"[{"id":"a","label":"A","expand":"more"},{"id":"","label":"Blank"}]"#,
            r#"{"more":{"title":"More","choices":[{"id":"x1","label":"x"}]}}"#,
        )
        .unwrap();
        assert_eq!(picked_id("1. A", &choices, &expansions).as_deref(), Some("a"));
        assert_eq!(picked_id("more\t1. x", &choices, &expansions).as_deref(), Some("x1"));
        assert_eq!(picked_id("gone\t1. x", &choices, &expansions), None);
        assert_eq!(picked_id("2. Blank", &choices, &expansions), None);
        assert_eq!(picked_id("A", &choices, &expansions), None);
    }
}
