//! The matcher against what `click-match.awk` made of the same pages and targets (tests/fixtures/gen-click-goldens.sh),
//! including the trace of an explain run and the cases where the awk dies.
use super::matcher::{Matcher, Options};
use std::collections::HashSet;
use std::path::PathBuf;

fn fixtures() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures")
}

fn unescape(field: &str) -> String {
    let mut out = String::new();
    let mut chars = field.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n') => out.push('\n'),
            Some('t') => out.push('\t'),
            Some('r') => out.push('\r'),
            Some(other) => out.push(other),
            None => out.push('\\'),
        }
    }
    out
}

struct Row {
    name: String,
    spans: bool,
    target: String,
    page: String,
    stdout: String,
    trace: String,
    status: String,
}

fn rows() -> Vec<Row> {
    let text = std::fs::read_to_string(fixtures().join("click-goldens.tsv")).expect("run gen-click-goldens.sh");
    text.lines()
        .map(|line| {
            let fields: Vec<&str> = line.split('\t').collect();
            let [name, spans, target, page, stdout, trace, status] = fields[..] else {
                panic!("malformed golden row: {line:?}")
            };
            let page = match page.strip_prefix('@') {
                Some(file) => std::fs::read_to_string(fixtures().join(format!("click/pages/{file}.tsv"))).unwrap(),
                None => format!("{}\n", unescape(page)),
            };
            Row {
                name: unescape(name),
                spans: spans == "1",
                target: unescape(target),
                page,
                stdout: unescape(stdout),
                trace: unescape(trace),
                status: status.to_string(),
            }
        })
        .collect()
}

/// stdout, trace and exit status of the matcher over the page, in the generator's formats.
fn run(row: &Row, explain: bool) -> (String, String, String) {
    let mut matcher = Matcher::new(&row.target, Options::new(row.spans, explain));
    let mut lines: Vec<&str> = row.page.split('\n').collect();
    if lines.last() == Some(&"") {
        lines.pop();
    }
    for line in lines {
        matcher.feed(line);
    }
    let output = matcher.finish();
    let stdout: Vec<String> = output.candidates.iter().map(|c| c.tsv()).collect();
    let trace: Vec<String> = output.trace.iter().map(|e| e.tsv()).collect();
    (
        stdout.join("\n"),
        trace.join("\n"),
        if output.error.is_some() { "2" } else { "0" }.to_string(),
    )
}

/// Some(description) when the matcher disagrees with the awk on this row.
fn mismatch(row: &Row) -> Option<String> {
    let (stdout, _, status) = run(row, false);
    let (explained, trace, _) = run(row, true);
    let mut wrong = Vec::new();
    if stdout != row.stdout {
        wrong.push(format!("stdout:\n  awk  {:?}\n  rust {stdout:?}", row.stdout));
    }
    if explained != row.stdout {
        wrong.push(format!(
            "stdout under explain:\n  awk  {:?}\n  rust {explained:?}",
            row.stdout
        ));
    }
    if trace != row.trace {
        wrong.push(format!("trace:\n  awk  {:?}\n  rust {trace:?}", row.trace));
    }
    if status != row.status {
        wrong.push(format!("exit: awk {} rust {status}", row.status));
    }
    (!wrong.is_empty()).then(|| {
        format!(
            "{} ({:?} on {:?}):\n{}",
            row.name,
            row.target,
            row.spans,
            wrong.join("\n")
        )
    })
}

#[test]
fn rust_matches_the_awk_goldens() {
    let rows = rows();
    assert!(
        rows.len() >= 381,
        "only {} golden rows: was the corpus lost?",
        rows.len()
    );
    let names: HashSet<&str> = rows.iter().map(|row| row.name.as_str()).collect();
    assert_eq!(names.len(), rows.len(), "golden names are not unique");
    let mismatches: Vec<String> = rows.iter().filter_map(mismatch).collect();
    assert!(
        mismatches.is_empty(),
        "{} of {} rows differ from the awk:\n{}",
        mismatches.len(),
        rows.len(),
        mismatches.iter().take(5).cloned().collect::<Vec<_>>().join("\n")
    );
}

/// A class with no candidate in its golden proves nothing: the comparison would pass on two empty outputs.
#[test]
fn every_class_has_a_row_with_candidates() {
    let rows = rows();
    for class in [
        "suite",
        "lookalike",
        "one_edit",
        "joined",
        "doubtful",
        "fillers",
        "plural_number",
        "apostrophe",
        "unicode",
        "repeated",
        "tasks",
        "close_clone",
        "scale",
        "negative_origin",
        "halfway",
        "exponent",
        "strips",
        "header_lines",
        "odd_rows",
        "label_truncation",
        "runs",
    ] {
        assert!(
            rows.iter()
                .any(|row| row.name.starts_with(&format!("{class}/")) && !row.stdout.is_empty()),
            "no {class} row with a candidate"
        );
        assert!(
            rows.iter()
                .any(|row| row.name.starts_with(&format!("{class}/")) && row.trace.contains("~cand")),
            "no {class} row with a traced candidate"
        );
    }
    for (class, status) in [("error", "2"), ("empty_target", "0"), ("header_only", "0")] {
        assert!(
            rows.iter()
                .any(|row| row.name.starts_with(&format!("{class}/")) && row.status == status),
            "no {class} row"
        );
    }
    let label = rows.iter().filter(|row| row.name.starts_with("label_truncation/"));
    assert!(
        label.into_iter().any(|row| row.stdout.contains("...")),
        "no truncated label"
    );
    assert!(rows.iter().any(|row| row.trace.contains("~drop")), "no ~drop row");
    assert!(
        rows.iter().any(|row| row.trace.contains("\tjoined\t")),
        "no joined candidate"
    );
    assert!(
        rows.iter().any(|row| row.trace.contains("\tspan\t")),
        "no span candidate"
    );
    assert!(
        rows.iter().any(|row| row.stdout.contains(" #2")),
        "no duplicate label suffix"
    );
}

/// The comparison must be able to fail: a golden whose expected text is changed no longer matches.
#[test]
fn a_changed_golden_is_a_mismatch() {
    let mut row = rows()
        .into_iter()
        .find(|row| !row.stdout.is_empty())
        .expect("a row with candidates");
    assert!(mismatch(&row).is_none());
    row.stdout.push('x');
    assert!(mismatch(&row).is_some());
    let mut row = rows()
        .into_iter()
        .find(|row| row.trace.contains("~cand"))
        .expect("a traced row");
    row.trace = row.trace.replace("~cand", "~kand");
    assert!(mismatch(&row).is_some());
    let mut row = rows().into_iter().find(|row| row.status == "2").expect("an error row");
    row.status = "0".to_string();
    assert!(mismatch(&row).is_some());
}
