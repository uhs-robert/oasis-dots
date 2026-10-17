//! `voxcmd ask hints [--listen] <label> <choices-json>`: numbered boxes on screen (was `voxcmd-hints`)
//!
//! Choices are `[{id, label, box: [left, top, width, height]}]` in global logical pixels; prints the picked id and
//! exits 0, or exits 1 on cancel. Answered by number key, click or a spoken reply. No bar, a choice without a box, more
//! choices than numbers, or a bar that refuses the overlay hands the whole pick to the text picker instead.
use super::{
    AskWith, Asking, PendingPick, PickChoice, StopSignals, Stopped, is_executable, qs_ipc_call, wait_or_terminate,
};
use crate::exit::CliError;
use crate::paths;
use serde::Serialize;
use serde_json::Value;
use std::path::PathBuf;
use std::process::Stdio;

/// One number per box; more choices go to the text picker.
const MAX_CHOICES: usize = 10;

/// What the text picker gets: it numbers the labels itself.
#[derive(Debug, Serialize)]
struct TextChoice {
    id: String,
    label: String,
}

#[derive(Serialize)]
struct HintsSpec<'a> {
    label: &'a str,
    result_path: &'a PathBuf,
    choices: Vec<HintBox<'a>>,
}

#[derive(Serialize)]
struct HintBox<'a> {
    label: &'a str,
    x: &'a Value,
    y: &'a Value,
    w: &'a Value,
    h: &'a Value,
}

/// The choices for the text picker, and numbered like its labels for the overlay, so a spoken ordinal or a number key
/// means the same box.
fn prepare(choices_json: &str) -> Result<(Vec<TextChoice>, Vec<PickChoice>), String> {
    let list: Value = serde_json::from_str(choices_json).map_err(|error| format!("not JSON: {error}"))?;
    let Value::Array(items) = list else {
        return Err("choices must be a JSON array".to_string());
    };
    let mut text_choices = Vec::new();
    let mut choices = Vec::new();
    for (index, item) in items.iter().enumerate() {
        if !matches!(item, Value::Object(_) | Value::Null) {
            return Err(format!("a choice is not an object: {item}"));
        }
        let text = |value: &Value| match value {
            Value::String(text) => text.clone(),
            other => other.to_string(),
        };
        let label = match &item["label"] {
            Value::Null | Value::Bool(false) => text(&item["id"]),
            label => text(label),
        };
        choices.push(PickChoice {
            id: text(&item["id"]),
            label: format!("{}. {label}", index + 1),
            expand: None,
            r#box: Some(item["box"].clone()),
        });
        text_choices.push(TextChoice {
            id: text(&item["id"]),
            label,
        });
    }
    Ok((text_choices, choices))
}

/// Every choice has a place on screen: four numbers.
fn drawable(choices: &[PickChoice]) -> bool {
    choices.len() <= MAX_CHOICES
        && choices.iter().all(|choice| match &choice.r#box {
            Some(Value::Array(edges)) => edges.len() == 4 && edges.iter().all(Value::is_number),
            _ => false,
        })
}

/// The id of the box the overlay or a reply named: "3", or a displayed label "3. Next - top right".
fn answered_id(answer: &str, choices: &[PickChoice]) -> Option<String> {
    let number = answer.split('.').next().unwrap_or_default();
    let valid = number.starts_with(|c: char| ('1'..='9').contains(&c)) && number.chars().all(|c| c.is_ascii_digit());
    let index = number.parse::<usize>().ok().filter(|_| valid)?.checked_sub(1)?;
    let id = &choices.get(index)?.id;
    (!id.is_empty()).then(|| id.clone())
}

/// `voxcmd ask hints`.
pub fn run(listen: bool, label: &str, choices_json: &str) -> Result<Option<String>, CliError> {
    let (text_choices, choices) = prepare(choices_json).map_err(|message| CliError::usage("ask hints", message))?;
    let text_choices = serde_json::to_string(&text_choices).expect("the choices serialize");
    let asker = AskWith::from_env();
    // A text picker asks instead: no bar to draw on, a choice with no place on screen, or more choices than numbers.
    if !is_executable(&paths::qs_ipc()) || !drawable(&choices) {
        let mut pick = asker.command("pick");
        if listen {
            pick.arg("--listen");
        }
        pick.args([label, &text_choices]);
        return Err(super::exec(pick));
    }
    let signals = StopSignals::hold();
    let mut overlay = Overlay {
        asking: Asking::create("hints")?,
        open: false,
    };
    match ask(&mut overlay, &signals, &asker, listen, label, &text_choices, &choices) {
        Ok(Ok(Answer::Picked(id))) => Ok(Some(id)),
        // The text picker printed the id itself.
        Ok(Ok(Answer::ByTextPicker)) => Ok(None),
        Ok(Ok(Answer::Cancelled)) | Err(Stopped) => Err(CliError::quiet("ask hints")),
        Ok(Err(error)) => Err(error),
    }
}

enum Answer {
    Picked(String),
    /// The bar refused the overlay and the text picker it handed the pick to was answered.
    ByTextPicker,
    Cancelled,
}

/// The ask and whether the overlay may be up: set before the bar is asked for it, not once it answers, so a signal
/// that lands during that call still takes the overlay down. The bar ignores a dismiss for one it never showed.
struct Overlay {
    asking: Asking,
    open: bool,
}

impl Overlay {
    /// The ask's own clean-up, then the overlay is dismissed: removed first, so nothing the bar writes afterwards can
    /// block on the FIFO.
    fn clean_up(&mut self) {
        self.asking.clean_up();
        if std::mem::replace(&mut self.open, false) {
            qs_ipc_call(&["clickhints".as_ref(), "dismiss".as_ref(), self.asking.fifo.as_os_str()]);
        }
    }
}

impl Drop for Overlay {
    fn drop(&mut self) {
        self.clean_up();
    }
}

fn ask(
    overlay: &mut Overlay,
    signals: &StopSignals,
    asker: &AskWith,
    listen: bool,
    label: &str,
    text_choices: &str,
    choices: &[PickChoice],
) -> Result<Result<Answer, CliError>, Stopped> {
    let asking = &overlay.asking;
    let spec_path = asking.dir.join("spec.json");
    let listen_again = asking.dir.join("listen-again");
    let spec = HintsSpec {
        label,
        result_path: &asking.fifo,
        choices: choices
            .iter()
            .map(|choice| {
                let edges = choice.r#box.as_ref().expect("a drawable choice has a box");
                HintBox {
                    label: &choice.label,
                    x: &edges[0],
                    y: &edges[1],
                    w: &edges[2],
                    h: &edges[3],
                }
            })
            .collect(),
    };
    if let Err(error) = std::fs::write(
        &spec_path,
        serde_json::to_string(&spec).expect("the spec serializes") + "\n",
    ) {
        return Ok(Err(CliError::failed("ask hints", error.to_string())));
    }
    let listen_again_text = if listen {
        listen_again.to_string_lossy().into_owned()
    } else {
        String::new()
    };
    if let Err(error) = asking.publish(&PendingPick {
        pid: std::process::id(),
        fifo: asking.fifo.clone(),
        label: label.to_string(),
        kind: Some("hints".to_string()),
        choices: choices.to_vec(),
        expansions: Default::default(),
        view: None,
        listen_again: Some(listen_again_text),
        verb: None,
    }) {
        return Ok(Err(error));
    }
    // A signal during setup ends the ask before the question shows, as the bash trap did.
    signals.check()?;
    if listen {
        let _ = std::fs::write(&listen_again, "");
        asking.start_reply_recording(signals)?;
    }
    overlay.open = true;
    let opened = qs_ipc_call(&["clickhints".as_ref(), "open".as_ref(), spec_path.as_os_str()]);
    signals.check()?;
    if opened != "ok" {
        // The text picker takes over the pending-pick file. This ask's own reply recording, if any, ends with it.
        overlay.open = false;
        let mut pick = asker.command("pick");
        pick.args([label, text_choices]).stdin(Stdio::null());
        let Ok(mut picker) = pick.spawn() else {
            return Ok(Ok(Answer::Cancelled));
        };
        let status = wait_or_terminate(&mut picker, signals)?;
        return Ok(Ok(if status.success() {
            Answer::ByTextPicker
        } else {
            Answer::Cancelled
        }));
    }
    // The overlay and a number key write the box number, a voice reply the displayed label.
    let timeout = super::timeout_setting("VOXCMD_HINTS_TIMEOUT", "120");
    let answer = overlay.asking.read_answer(&timeout, signals)?;
    overlay.clean_up();
    Ok(Ok(
        answered_id(&answer, choices).map_or(Answer::Cancelled, Answer::Picked)
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn boxes_keep_their_numbers_as_given_and_labels_are_numbered() {
        let (text, choices) =
            prepare(r#"[{"id":"a","label":"Next","box":[300,200,70.5,22]},{"id":1,"box":[0,0,1,1]}]"#).unwrap();
        assert_eq!(
            serde_json::to_string(&text).unwrap(),
            r#"[{"id":"a","label":"Next"},{"id":"1","label":"1"}]"#
        );
        assert_eq!(choices[1].label, "2. 1");
        assert_eq!(
            serde_json::to_string(&choices[0]).unwrap(),
            r#"{"id":"a","label":"1. Next","box":[300,200,70.5,22]}"#
        );
        assert!(drawable(&choices));
    }

    #[test]
    fn a_missing_or_bad_box_or_too_many_choices_is_not_drawable() {
        let (_, no_box) = prepare(r#"[{"id":"a","label":"A"}]"#).unwrap();
        let (_, short) = prepare(r#"[{"id":"a","box":[1,2,3]}]"#).unwrap();
        let (_, text) = prepare(r#"[{"id":"a","box":[1,2,3,"4"]}]"#).unwrap();
        let many: Vec<_> = (0..11)
            .map(|i| serde_json::json!({"id": i, "box": [i, 0, 8, 8]}))
            .collect();
        let (_, many) = prepare(&serde_json::to_string(&many).unwrap()).unwrap();
        for choices in [no_box, short, text, many] {
            assert!(!drawable(&choices));
        }
    }

    #[test]
    fn the_answer_is_a_box_number_or_a_numbered_label() {
        let (_, choices) = prepare(r#"[{"id":"a","box":[0,0,1,1]},{"id":"b","box":[0,0,1,1]}]"#).unwrap();
        assert_eq!(answered_id("2", &choices).as_deref(), Some("b"));
        assert_eq!(answered_id("1. Next - top", &choices).as_deref(), Some("a"));
        for cancel in ["", "0", "3", "02", "x", "-1", "99999999999999999999999"] {
            assert_eq!(answered_id(cancel, &choices), None, "{cancel:?}");
        }
    }
}
