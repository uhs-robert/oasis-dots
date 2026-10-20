//! The trace `explain --window` prints for a click phrase: what was captured, what each matcher pass made of it, which
//! candidates word matching kept, which the covering check dropped, and what the click would do. The port of
//! click.sh's `explain_render`; the text is byte for byte the bash's.
//!
//! The `screen_text` provider fills a `ClickTrace` while it answers the routing, so the trace and the route they
//! explain come from one capture and one reading of it.
use super::covering::Cover;
use super::driver::CaptureInfo;
use super::matcher::{Kind, Pass, TraceEvent};
use crate::hooks::Candidate;
use crate::route::resolve::word_match;
use crate::route::router::needs_pick_among;
use serde::Serialize;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::fmt::Write as _;
use std::sync::{Arc, Mutex};

/// Where the provider leaves the traces of the clicks it answered, in the order it answered them.
pub type ExplainSink = Arc<Mutex<Vec<ClickTrace>>>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TraceKind {
    /// The screen was read and matched.
    Run,
    /// Nothing in the target is worth looking for: the screen was not read.
    FillerOnly,
    /// The capture or the OCR failed.
    Error,
}

/// What click-ocr's `#info` line says, as it prints it.
#[derive(Debug, Clone, Serialize)]
pub struct InfoTrace {
    pub class: String,
    pub mode: String,
    pub size: String,
    pub image: String,
    pub scale_x: String,
    pub scale_y: String,
    pub inverted: bool,
    pub strips: usize,
    pub ocr_ms: u64,
}

impl From<&CaptureInfo> for InfoTrace {
    fn from(info: &CaptureInfo) -> Self {
        Self {
            class: info.class.clone(),
            mode: info.mode.name().to_string(),
            size: format!("{}x{}", info.size.0, info.size.1),
            image: format!("{}x{}", info.image.0, info.image.1),
            scale_x: format!("{:.3}", info.image.0 as f64 / info.size.0 as f64),
            scale_y: format!("{:.3}", info.image.1 as f64 / info.size.1 as f64),
            inverted: info.inverted,
            strips: info.strips,
            ocr_ms: info.ocr_ms,
        }
    }
}

/// Word matching's verdict on the candidate at a point in one pass.
#[derive(Debug, Clone, Serialize)]
pub struct VerdictAt {
    /// "x,y", the first two fields of the candidate's id.
    pub point: String,
    pub kept: bool,
    pub weak: bool,
    pub verdict: String,
}

#[derive(Debug, Clone)]
pub struct PassTrace {
    pub pass: Pass,
    pub events: Vec<TraceEvent>,
    pub verdicts: Vec<VerdictAt>,
}

/// What the covering check made of the point of a candidate of the pass that was used.
#[derive(Debug, Clone, Serialize)]
pub struct CoveredAt {
    pub point: String,
    pub by: Option<String>,
}

impl CoveredAt {
    pub fn new(point: String, cover: Option<Cover>) -> Self {
        Self {
            point,
            by: cover.map(|cover| cover.to_string()),
        }
    }
}

#[derive(Debug, Clone)]
pub struct ClickTrace {
    pub target: String,
    pub kind: TraceKind,
    pub info: Option<InfoTrace>,
    pub passes: Vec<PassTrace>,
    /// The pass whose candidates went on to the covering check.
    pub used_pass: Pass,
    pub covered: Vec<CoveredAt>,
    pub outcome: String,
}

fn pass_name(pass: Pass) -> &'static str {
    match pass {
        Pass::Whole => "whole",
        Pass::Spans => "spans",
    }
}

fn kind_name(kind: Kind) -> &'static str {
    match kind {
        Kind::Word => "word",
        Kind::Joined => "joined",
        Kind::Span => "span",
    }
}

/// The first two fields of a candidate id: the point it clicks.
pub fn point_of(id: &str) -> String {
    id.split(',').take(2).collect::<Vec<_>>().join(",")
}

/// What a click would do with the candidates left after covering. Hints are for several or weak matches, as the router
/// decides with `needs_pick_among`.
pub fn outcome_of(visible: &[Candidate], target: &str, ignored: &[String]) -> String {
    if let Some(first) = visible.first() {
        if let Some(reason) = first.id.strip_prefix("error:") {
            return format!("capture or OCR failed ({reason}); a toast says the click failed");
        }
        if first.id.starts_with("covered:") {
            return "covered: every candidate is under another window or a reserved edge".to_string();
        }
    }
    let options = word_match(target, visible, ignored).unwrap_or_default();
    if options.is_empty() {
        "not on screen".to_string()
    } else if needs_pick_among(options.len(), options.iter().any(|option| option.weak)) {
        let weak = if options.len() == 1 {
            ", a weak match: asks \"this one?\""
        } else {
            ""
        };
        format!(
            "overlay with {}{weak} (the picker, if the bar cannot draw it or there are more than 10)",
            options.len()
        )
    } else {
        format!("click at {}", point_of(&options[0].id))
    }
}

impl ClickTrace {
    /// A target with no word to look for: the screen is not read.
    pub fn filler_only(target: &str) -> Self {
        Self {
            target: target.to_string(),
            kind: TraceKind::FillerOnly,
            info: None,
            passes: Vec::new(),
            used_pass: Pass::Whole,
            covered: Vec::new(),
            outcome: "filler-only target: the screen is not read, and Keybinds' click binds get it".to_string(),
        }
    }

    /// The capture or the OCR failed with `message`.
    pub fn failed(target: &str, message: &str) -> Self {
        Self {
            target: target.to_string(),
            kind: TraceKind::Error,
            info: None,
            passes: Vec::new(),
            used_pass: Pass::Whole,
            covered: Vec::new(),
            outcome: format!("capture or OCR failed ({message}); a toast says the click failed"),
        }
    }

    /// The verdict on the candidate at `point` of `pass`, worded as the bash `explain_verdict_text`. Two candidates at
    /// one point share a verdict, the later one's, as they did in the bash's associative array.
    fn verdict_text(&self, pass: &PassTrace, point: &str, kind: &str) -> String {
        let lead = match kind {
            "span" => "sub-span, ",
            "joined" => "joined letters, ",
            _ => "",
        };
        let Some(verdict) = pass.verdicts.iter().rev().find(|one| one.point == point) else {
            return format!("{lead}no verdict");
        };
        let text = if verdict.kept {
            let (strength, detail) = verdict.verdict.split_once(": ").unwrap_or((&verdict.verdict, ""));
            let mut text = format!("kept {strength} ({detail})");
            let cover = self
                .covered
                .iter()
                .rev()
                .find(|one| one.point == point)
                .and_then(|one| one.by.as_deref());
            if pass.pass == self.used_pass
                && let Some(cover) = cover
            {
                let _ = write!(text, ", then dropped: covered by {cover}");
            }
            text
        } else if verdict.verdict.starts_with("dropped:") {
            verdict.verdict.clone()
        } else {
            format!("dropped: {}", verdict.verdict)
        };
        format!("{lead}{text}")
    }

    /// The section as the bash printed it.
    pub fn text(&self) -> String {
        let mut out = String::new();
        if let Some(info) = &self.info {
            let class = if info.class.is_empty() { "?" } else { &info.class };
            let inverted = if info.inverted { "inverted" } else { "not inverted" };
            let _ = writeln!(out, "window   {class} {}", info.size);
            let _ = writeln!(
                out,
                "capture  {}, image {}, scale x{} y{}, {inverted}, {} strip(s), OCR {} ms",
                info.mode, info.image, info.scale_x, info.scale_y, info.strips, info.ocr_ms
            );
        }
        let _ = writeln!(out, "target   \"{}\"", self.target);
        for pass in &self.passes {
            let mut pending: HashMap<usize, Vec<(String, &str, String)>> = HashMap::new();
            for event in &pass.events {
                let fields = event.tsv();
                let fields: Vec<&str> = fields.split('\t').collect();
                match event {
                    TraceEvent::Pass(Pass::Whole) => out.push_str("pass 1: whole runs\n"),
                    TraceEvent::Pass(Pass::Spans) => {
                        out.push_str("pass 2: sub-spans of runs (no whole run was kept by word matching)\n");
                    }
                    TraceEvent::Drop { .. } => {
                        // ~drop conf text x y reason
                        let _ = writeln!(
                            out,
                            "  word \"{}\" (conf {}) near {},{}: dropped, {}",
                            fields[2], fields[1], fields[3], fields[4], fields[5]
                        );
                    }
                    TraceEvent::Cand {
                        run_id,
                        x,
                        y,
                        kind,
                        match_text,
                    } => pending.entry(*run_id).or_default().push((
                        format!("{x},{y}"),
                        kind_name(*kind),
                        match_text.clone(),
                    )),
                    TraceEvent::Run { id, words, outcome } => {
                        let _ = writeln!(out, "  run {id}: {words}");
                        match pending.get(id) {
                            Some(found) if !found.is_empty() => {
                                for (point, kind, text) in found {
                                    let _ = writeln!(
                                        out,
                                        "    candidate {point} \"{text}\": {}",
                                        self.verdict_text(pass, point, kind)
                                    );
                                }
                            }
                            _ => {
                                let _ = writeln!(out, "    {outcome}");
                            }
                        }
                    }
                }
            }
        }
        let _ = writeln!(out, "outcome  {}", self.outcome);
        out.truncate(out.trim_end_matches('\n').len());
        out
    }

    pub fn json(&self) -> Value {
        let passes: Vec<Value> = self
            .passes
            .iter()
            .map(|pass| {
                json!({
                    "pass": pass_name(pass.pass),
                    "events": pass.events.iter().map(event_json).collect::<Vec<_>>(),
                    "verdicts": pass.verdicts,
                })
            })
            .collect();
        json!({
            "target": self.target,
            "kind": self.kind,
            "info": self.info,
            "passes": passes,
            "used_pass": pass_name(self.used_pass),
            "covered": self.covered,
            "outcome": self.outcome,
        })
    }
}

fn event_json(event: &TraceEvent) -> Value {
    match event {
        TraceEvent::Pass(pass) => json!({"event": "pass", "pass": pass_name(*pass)}),
        TraceEvent::Drop {
            conf,
            text,
            x,
            y,
            reason,
        } => json!({"event": "drop", "conf": conf, "text": text, "x": x, "y": y, "reason": reason}),
        TraceEvent::Run { id, words, outcome } => {
            json!({"event": "run", "id": id, "words": words, "outcome": outcome})
        }
        TraceEvent::Cand {
            run_id,
            x,
            y,
            kind,
            match_text,
        } => json!({"event": "candidate", "run_id": run_id, "x": x, "y": y, "kind": kind_name(*kind),
                    "match_text": match_text}),
    }
}

/// The sections of an `explain --window` run after the routing text, one per click the provider answered.
pub fn sections_text(traces: &[ClickTrace]) -> String {
    if traces.is_empty() {
        return "click     not reached: the phrase did not route to the Click integration".to_string();
    }
    traces.iter().map(ClickTrace::text).collect::<Vec<_>>().join("\n\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn candidate(id: &str, label: &str, weak: bool) -> Candidate {
        Candidate {
            id: id.to_string(),
            label: label.to_string(),
            match_text: Some(label.to_string()),
            weak,
        }
    }

    #[test]
    fn a_filler_only_target_prints_two_lines() {
        assert_eq!(
            ClickTrace::filler_only("it").text(),
            "target   \"it\"\noutcome  filler-only target: the screen is not read, and Keybinds' click binds get it"
        );
    }

    #[test]
    fn a_failure_prints_the_target_then_the_reason() {
        assert_eq!(
            ClickTrace::failed("sign in", "no such window").text(),
            "target   \"sign in\"\noutcome  capture or OCR failed (no such window); a toast says the click failed"
        );
    }

    #[test]
    fn the_outcome_follows_the_routers_pick_rule() {
        let strong = [candidate("175,82,left,1,2,3,4", "sign in", false)];
        assert_eq!(outcome_of(&strong, "sign in", &[]), "click at 175,82");
        let weak = [candidate("1,2,left,1,2,3,4", "open settings", false)];
        assert_eq!(
            outcome_of(&weak, "settings", &[]),
            "overlay with 1, a weak match: asks \"this one?\" (the picker, if the bar cannot draw it or there are more than 10)"
        );
        let two = [
            candidate("1,2,left,1,2,3,4", "next", false),
            candidate("5,6,left,1,2,3,4", "next", false),
        ];
        assert!(outcome_of(&two, "next", &[]).starts_with("overlay with 2 (the picker"));
        assert_eq!(outcome_of(&strong, "banana", &[]), "not on screen");
        assert_eq!(
            outcome_of(&[candidate("covered:", "covered", false)], "x", &[]),
            "covered: every candidate is under another window or a reserved edge"
        );
        assert_eq!(
            outcome_of(&[candidate("error:no focused window", "x", false)], "x", &[]),
            "capture or OCR failed (no focused window); a toast says the click failed"
        );
    }

    fn run_trace(kept: bool, verdict: &str, cover: Option<Cover>) -> ClickTrace {
        ClickTrace {
            target: "sign in".to_string(),
            kind: TraceKind::Run,
            info: None,
            passes: vec![PassTrace {
                pass: Pass::Whole,
                events: vec![
                    TraceEvent::Pass(Pass::Whole),
                    TraceEvent::Cand {
                        run_id: 1,
                        x: 175,
                        y: 82,
                        kind: Kind::Joined,
                        match_text: "sign in".to_string(),
                    },
                    TraceEvent::Run {
                        id: 1,
                        words: "sign(95) in(95)".to_string(),
                        outcome: "kept".to_string(),
                    },
                    TraceEvent::Run {
                        id: 2,
                        words: "sign(95)".to_string(),
                        outcome: "no candidate".to_string(),
                    },
                ],
                verdicts: vec![VerdictAt {
                    point: "175,82".to_string(),
                    kept,
                    weak: false,
                    verdict: verdict.to_string(),
                }],
            }],
            used_pass: Pass::Whole,
            covered: vec![CoveredAt::new("175,82".to_string(), cover)],
            outcome: "click at 175,82".to_string(),
        }
    }

    #[test]
    fn a_kept_candidate_names_its_strength_and_a_cover() {
        let text = run_trace(true, "strong: same words", Some(Cover::ReservedEdge)).text();
        assert_eq!(
            text,
            "target   \"sign in\"\npass 1: whole runs\n  run 1: sign(95) in(95)\n    candidate 175,82 \"sign in\": joined letters, kept strong (same words), then dropped: covered by a reserved edge (the bar)\n  run 2: sign(95)\n    no candidate\noutcome  click at 175,82"
        );
    }

    #[test]
    fn a_dropped_candidate_prints_the_reason_with_one_dropped_prefix() {
        let plain = run_trace(false, "near miss only: no spoken word is in it", None).text();
        assert!(plain.contains(": joined letters, dropped: near miss only"), "{plain}");
        let capped = run_trace(false, "dropped: past the ten best weak matches", None).text();
        assert!(
            capped.contains(": joined letters, dropped: past the ten best weak matches"),
            "{capped}"
        );
        assert!(!capped.contains("dropped: dropped"), "{capped}");
        let none = ClickTrace {
            passes: vec![PassTrace {
                verdicts: Vec::new(),
                ..run_trace(true, "", None).passes.remove(0)
            }],
            ..run_trace(true, "", None)
        };
        assert!(none.text().contains("joined letters, no verdict"));
    }

    #[test]
    fn the_json_is_one_object_with_stable_keys() {
        let value = run_trace(true, "strong: same words", None).json();
        for key in ["target", "kind", "info", "passes", "used_pass", "covered", "outcome"] {
            assert!(value.get(key).is_some(), "{key}");
        }
        assert_eq!(value["kind"], "run");
        assert_eq!(value["passes"][0]["pass"], "whole");
        assert_eq!(value["passes"][0]["events"][1]["event"], "candidate");
        assert_eq!(value["passes"][0]["verdicts"][0]["verdict"], "strong: same words");
        assert!(serde_json::to_string(&value).is_ok());
    }

    #[test]
    fn no_trace_at_all_is_the_not_reached_line() {
        assert_eq!(
            sections_text(&[]),
            "click     not reached: the phrase did not route to the Click integration"
        );
    }
}
