//! `screen_text`: the candidates of a click phrase are the text visible in the focused window. The port of click.sh's
//! `candidates()`.
//!
//! It captures and reads the window, matches the spoken target against the text, and drops what another window or the
//! bar hides. A failure and "everything found is hidden" are each one candidate whose id says so (`error:<why>`,
//! `covered:`), which `click_at` reports: an empty list would read as "not on screen" and hand the phrase on.
use super::capture::Tools;
use super::covering;
use super::driver::{self, Mode, WindowSel};
use super::explain::{
    ClickTrace, CoveredAt, ExplainSink, InfoTrace, PassTrace, TraceKind, VerdictAt, outcome_of, point_of,
};
use super::matcher::{Options, Pass, match_stream};
use super::words::FILLER_WORDS;
use crate::config::schema::{Builtin, Button, Candidates, Integration, Provider};
use crate::hooks::{Candidate, HookQuery, HookRun, Hooks, Lookup};
use crate::hypr;
use crate::route::resolve::judge;
use serde_json::{Value, json};
use std::time::Instant;

pub struct BuiltinHooks {
    tools: Tools,
    /// `explain --window`: where each answer leaves its trace, and which window it reads. A click proper has neither.
    explain: Option<ExplainSink>,
    window: WindowSel,
}

impl Default for BuiltinHooks {
    fn default() -> Self {
        Self {
            tools: Tools::default(),
            explain: None,
            window: WindowSel::Focused,
        }
    }
}

impl BuiltinHooks {
    /// Hooks for `explain --window`: they read `window`, write no click-target, and record a trace of every answer.
    pub fn tracing(window: WindowSel, sink: ExplainSink) -> Self {
        Self {
            explain: Some(sink),
            window,
            ..Self::default()
        }
    }

    fn screen_text(&self, integration: &Integration, query: &HookQuery) -> HookRun {
        let mut run = HookRun::unhooked(
            integration,
            query.action,
            &format!("screen_text {} {}", query.action, query.target),
        );
        let ignored = &integration.settings.match_ignore_words;
        run.exit = Some(0);
        // Nothing to look for: the screen is not read at all.
        run.lookup = Lookup::Candidates(Vec::new());
        if has_target_word(query.target, ignored) {
            let started = Instant::now();
            let (found, trace) = self.read(query.target, button_of(integration, query.action), ignored);
            run.millis = started.elapsed().as_secs_f64() * 1000.0;
            run.lines.clone_from(&found);
            run.lookup = Lookup::Candidates(found);
            self.record(trace);
        } else {
            self.record(Some(ClickTrace::filler_only(query.target)));
        }
        run
    }

    fn record(&self, trace: Option<ClickTrace>) {
        if let (Some(sink), Some(trace)) = (&self.explain, trace) {
            sink.lock().expect("no panic holds the lock").push(trace);
        }
    }

    /// The candidates for the target in the window, and, under `explain --window`, the trace of how they were found.
    fn read(&self, target: &str, button: Button, ignored: &[String]) -> (Vec<Candidate>, Option<ClickTrace>) {
        let explaining = self.explain.is_some();
        // The capture writes click-target even for a dry run: a route is what records the window the click will check.
        // A trace is not a route to a click, so it leaves the record alone.
        let mode = if explaining { Mode::Explain } else { Mode::Click };
        let captured = match driver::capture_page(&self.window, mode, None, &self.tools) {
            Ok(captured) => captured,
            Err(error) => {
                let candidate = error_candidate(&error.message, target);
                let trace = explaining.then(|| ClickTrace::failed(target, &candidate.label));
                return (vec![candidate], trace);
            }
        };
        let stream = String::from_utf8_lossy(&captured.stream);
        // One snapshot of the focused window serves the capture and the covering check (the bash asked twice).
        let clients = hypr::clients().unwrap_or_else(|| json!([]));
        let monitors = hypr::monitors().unwrap_or_else(|| json!([]));
        let reading = read_stream(
            &stream,
            &captured.window,
            &clients,
            &monitors,
            button,
            target,
            ignored,
            explaining,
        );
        let trace = explaining.then(|| ClickTrace {
            target: target.to_string(),
            kind: TraceKind::Run,
            info: Some(InfoTrace::from(&captured.info)),
            outcome: outcome_of(&reading.candidates, target, ignored),
            passes: reading.passes,
            used_pass: reading.used,
            covered: reading.covered,
        });
        (reading.candidates, trace)
    }
}

impl Hooks for BuiltinHooks {
    fn candidates(&self, integration: &Integration, query: &HookQuery) -> HookRun {
        match integration.candidates_for(query.action) {
            Some(Candidates::Builtin(Provider::ScreenText)) => self.screen_text(integration, query),
            _ => HookRun::unhooked(integration, query.action, ""),
        }
    }

    fn surface_open(&self, _integration: &Integration) -> bool {
        false
    }
}

/// The button the action clicks with: the one its `click_at <button>` names, else the one its name says.
pub fn button_of(integration: &Integration, action: &str) -> Button {
    if let Some(Builtin::ClickAt(Some(button))) = integration.actions.get(action).and_then(|declared| declared.builtin)
    {
        return button;
    }
    match action {
        "right_click" => Button::Right,
        "double_click" => Button::Double,
        "triple_click" => Button::Triple,
        _ => Button::Left,
    }
}

/// Whether the spoken text holds a word that is neither filler nor ignored. Words are runs of `[a-z0-9]`, so an
/// apostrophe splits one ("don't" is `don` and `t`), unlike in the matcher.
pub fn has_target_word(target: &str, ignored: &[String]) -> bool {
    target
        .to_lowercase()
        .split(|character: char| !(character.is_ascii_lowercase() || character.is_ascii_digit()))
        .filter(|word| !word.is_empty())
        .any(|word| !FILLER_WORDS.contains(&word) && !ignored.iter().any(|ignored| ignored == word))
}

fn error_candidate(message: &str, target: &str) -> Candidate {
    // The reason is the last line a tool printed, and something when it printed none.
    let message = message
        .lines()
        .next_back()
        .filter(|line| !line.is_empty())
        .unwrap_or("capture failed");
    Candidate {
        id: format!("error:{message}"),
        label: message.to_string(),
        match_text: Some(target.to_string()),
        weak: false,
    }
}

/// A point and what the matcher made of it.
struct Found {
    x: i64,
    y: i64,
    candidate: Candidate,
}

/// What the matcher and the covering check made of the stream: the candidates a click is offered, and, when asked, the
/// trace of how.
pub struct Reading {
    pub candidates: Vec<Candidate>,
    pub passes: Vec<PassTrace>,
    pub used: Pass,
    pub covered: Vec<CoveredAt>,
}

/// The matcher's candidates over the stream: whole runs first, then, when word matching keeps none of those, the
/// sub-spans of runs (the target may be part of a longer run of words, "2 tasks" in a sentence). When there are no
/// spans either, the whole runs stay. Returns the passes it ran and the one whose candidates it kept.
fn matched(
    stream: &str,
    target: &str,
    button: Button,
    ignored: &[String],
    explain: bool,
) -> (Vec<Found>, Vec<PassTrace>, Pass) {
    let pass = |spans_only: bool| -> (Vec<Found>, PassTrace) {
        let output = match_stream(stream, target, Options::new(spans_only, explain));
        // The awk dying leaves jq an empty input and so an empty list.
        let found: Vec<Found> = if output.error.is_some() {
            Vec::new()
        } else {
            output
                .candidates
                .iter()
                .map(|found| Found {
                    x: found.x,
                    y: found.y,
                    candidate: Candidate {
                        id: found.id(button.name()),
                        label: found.label.clone(),
                        match_text: Some(found.match_text.clone()),
                        weak: false,
                    },
                })
                .collect()
        };
        let trace = PassTrace {
            pass: if spans_only { Pass::Spans } else { Pass::Whole },
            events: output.trace,
            verdicts: Vec::new(),
        };
        (found, trace)
    };
    // The verdicts are word matching's own, so the trace and the real pick read the same rules.
    let judged = |found: &[Found], trace: &mut PassTrace| -> bool {
        let candidates: Vec<Candidate> = found.iter().map(|found| found.candidate.clone()).collect();
        let judged = judge(target, &candidates, ignored).unwrap_or_default();
        if explain {
            trace.verdicts = judged
                .iter()
                .map(|one| VerdictAt {
                    point: point_of(&one.candidate.id),
                    kept: one.kept,
                    weak: one.weak,
                    verdict: one.verdict.to_string(),
                })
                .collect();
        }
        judged.iter().any(|one| one.kept)
    };
    let (whole, mut whole_trace) = pass(false);
    if judged(&whole, &mut whole_trace) {
        return (whole, vec![whole_trace], Pass::Whole);
    }
    let (spans, mut spans_trace) = pass(true);
    judged(&spans, &mut spans_trace);
    let passes = vec![whole_trace, spans_trace];
    if spans.is_empty() {
        (whole, passes, Pass::Whole)
    } else {
        (spans, passes, Pass::Spans)
    }
}

/// The candidates for the target over click-ocr's stream of `window`, with what is drawn over it taken out, and with
/// `explain` the trace of how they came to be.
#[allow(
    clippy::too_many_arguments,
    reason = "one reading of one capture; a struct would only rename the arguments"
)]
pub fn read_stream(
    stream: &str,
    window: &Value,
    clients: &Value,
    monitors: &Value,
    button: Button,
    target: &str,
    ignored: &[String],
    explain: bool,
) -> Reading {
    let (found, passes, used) = matched(stream, target, button, ignored, explain);
    let seen = found.len();
    let covers: Vec<Option<covering::Cover>> = found
        .iter()
        .map(|found| covering::covered_by(found.x, found.y, window, clients, monitors))
        .collect();
    let covered: Vec<CoveredAt> = if explain {
        found
            .iter()
            .zip(&covers)
            .map(|(found, cover)| CoveredAt::new(point_of(&found.candidate.id), *cover))
            .collect()
    } else {
        Vec::new()
    };
    let visible: Vec<Candidate> = found
        .into_iter()
        .zip(&covers)
        .filter(|(_, cover)| cover.is_none())
        .map(|(found, _)| found.candidate)
        .collect();
    let candidates = if visible.is_empty() && seen > 0 {
        vec![Candidate {
            id: "covered:".to_string(),
            label: "covered".to_string(),
            match_text: Some(target.to_string()),
            weak: false,
        }]
    } else {
        visible
    };
    Reading {
        candidates,
        passes,
        used,
        covered,
    }
}

/// `read_stream` without the trace.
#[cfg(test)]
pub fn candidates_in(
    stream: &str,
    window: &Value,
    clients: &Value,
    monitors: &Value,
    button: Button,
    target: &str,
    ignored: &[String],
) -> Vec<Candidate> {
    read_stream(stream, window, clients, monitors, button, target, ignored, false).candidates
}

#[cfg(test)]
mod tests {
    use super::*;

    fn no_one() -> Vec<String> {
        Vec::new()
    }

    #[test]
    fn a_target_of_filler_and_ignored_words_has_no_word() {
        let ignored: Vec<String> = ["left", "right", "middle", "here", "and", "drag", "hold"]
            .map(String::from)
            .to_vec();
        for target in ["it", "the", "left", "here and it", "", "!!", "left and the"] {
            assert!(!has_target_word(target, &ignored), "{target:?}");
        }
        for target in ["sign in", "left button", "don't", "Sign", "2", "naïve"] {
            assert!(has_target_word(target, &ignored), "{target:?}");
        }
    }

    #[test]
    fn an_apostrophe_splits_a_word_here() {
        // "don't" is "don" and "t", neither filler; the matcher, which drops the apostrophe, reads it as "dont".
        assert!(has_target_word("don't", &no_one()));
    }

    #[test]
    fn an_error_candidate_carries_the_last_line_or_a_default() {
        let candidate = error_candidate("first\nno focused window", "sign in");
        assert_eq!(candidate.id, "error:no focused window");
        assert_eq!(candidate.label, "no focused window");
        assert_eq!(candidate.match_text.as_deref(), Some("sign in"));
        assert_eq!(error_candidate("", "x").id, "error:capture failed");
    }

    // Tesseract's tsv for "Sign in" at 80,40 and "Settings" at 160,120 in a 160x96 window at 100,50 captured at 1.6.
    fn stream() -> String {
        let mut text = String::from("#window 100 50 160 96 256 154\n#strip 0 0 0 154\n");
        text.push_str(
            "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n",
        );
        for (block, word, left, top, width, conf, label) in [
            (1, 1, 80, 40, 48, 95, "Sign"),
            (1, 2, 136, 40, 24, 95, "in"),
            (2, 1, 160, 120, 96, 95, "Settings"),
        ] {
            text.push_str(&format!(
                "5\t1\t{block}\t1\t1\t{word}\t{left}\t{top}\t{width}\t24\t{conf}\t{label}\n"
            ));
        }
        text
    }

    fn window() -> Value {
        json!({"address": "0x2001", "at": [100, 50], "size": [160, 96], "floating": false, "pinned": false,
               "workspace": {"id": 1}})
    }

    fn monitors(reserved: [i64; 4]) -> Value {
        json!([{"width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": reserved}])
    }

    fn lookup(target: &str, clients: &Value, monitors: &Value) -> Vec<String> {
        candidates_in(&stream(), &window(), clients, monitors, Button::Left, target, &no_one())
            .into_iter()
            .map(|candidate| candidate.id)
            .collect()
    }

    #[test]
    fn a_strong_match_is_an_id_with_the_point_the_button_and_the_box() {
        let ids = lookup("sign in", &json!([]), &monitors([0, 0, 0, 0]));
        assert_eq!(ids.len(), 1);
        assert!(ids[0].starts_with("175,82,left,"), "{ids:?}");
    }

    #[test]
    fn the_button_is_the_third_field() {
        let found = candidates_in(
            &stream(),
            &window(),
            &json!([]),
            &monitors([0; 4]),
            Button::Triple,
            "settings",
            &no_one(),
        );
        assert!(found[0].id.starts_with("230,132,triple,"), "{found:?}");
    }

    #[test]
    fn text_that_is_not_there_is_an_empty_list_not_a_sentinel() {
        assert_eq!(lookup("banana", &json!([]), &monitors([0; 4])), Vec::<String>::new());
    }

    #[test]
    fn a_window_over_one_candidate_leaves_the_other() {
        let floating = json!([{"address": "0x3001", "at": [150, 50], "size": [60, 60], "floating": true,
                               "pinned": false, "workspace": {"id": 1}, "mapped": true, "hidden": false}]);
        assert!(lookup("sign in", &floating, &monitors([0; 4]))[0].starts_with("covered:"));
        assert!(lookup("settings", &floating, &monitors([0; 4]))[0].starts_with("230,132,"));
    }

    #[test]
    fn everything_hidden_is_one_candidate_that_says_so_and_the_bar_hides_like_a_window() {
        let ids = lookup("sign in", &json!([]), &monitors([0, 100, 0, 0]));
        assert_eq!(ids, ["covered:"]);
        let found = candidates_in(
            &stream(),
            &window(),
            &json!([]),
            &monitors([0, 100, 0, 0]),
            Button::Left,
            "sign in",
            &no_one(),
        );
        assert_eq!(found[0].label, "covered");
        assert_eq!(found[0].match_text.as_deref(), Some("sign in"));
    }

    #[test]
    fn a_second_monitor_does_not_hide_the_first_monitors_text() {
        let monitors = json!([
            {"width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": [0, 0, 0, 0]},
            {"width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 1920, "y": 0, "reserved": [0, 300, 0, 0]},
        ]);
        assert!(lookup("sign in", &json!([]), &monitors)[0].starts_with("175,82,"));
    }
}
