//! The strip arithmetic, the tool command lines and the `#info` line against what the bash `click-ocr` produced over a
//! grid of windows, scales and brightness (tests/fixtures/ocr-plan-goldens.tsv, frozen; the generator is gone).
use super::capture::{CaptureMode, Geometry};
use super::driver::{CaptureInfo, strip_line, window_line};
use super::strips::{self, DARK_BELOW};
use std::path::Path;

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
    window: (i64, i64),
    mean: f64,
    stream: String,
    calls: String,
}

fn rows() -> Vec<Row> {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/ocr-plan-goldens.tsv");
    let text =
        std::fs::read_to_string(path).expect("the golden file is missing; goldens are frozen, restore it from git");
    text.lines()
        .map(|line| {
            let fields: Vec<&str> = line.split('\t').collect();
            let [name, w, h, mean, stream, calls] = fields[..] else {
                panic!("malformed golden row: {line:?}")
            };
            Row {
                name: name.to_string(),
                window: (w.parse().unwrap(), h.parse().unwrap()),
                mean: mean.parse().unwrap(),
                stream: unescape(stream),
                calls: unescape(calls),
            }
        })
        .collect()
}

/// The image size, which the golden holds on its `#window` line.
fn image_of(row: &Row) -> (i64, i64) {
    let fields: Vec<&str> = row.stream.lines().next().unwrap().split(' ').collect();
    (fields[5].parse().unwrap(), fields[6].parse().unwrap())
}

fn geometry_of(row: &Row) -> Geometry {
    Geometry {
        x: 10,
        y: 20,
        w: row.window.0,
        h: row.window.1,
    }
}

fn expected_calls(row: &Row) -> String {
    let work = Path::new("<work>");
    let (image_w, image_h) = image_of(row);
    let cuts = strips::plan(image_w, image_h, row.window.0);
    let mut calls = vec![format!(
        "magick {}",
        strips::magick_cut_args(work, image_w, &cuts).join(" ")
    )];
    for cut in &cuts {
        let file = strips::strip_file(work, cut);
        if row.mean < DARK_BELOW {
            calls.push(format!("magick {}", strips::negate_args(&file).join(" ")));
            calls.push(format!("tesseract {}", strips::tesseract_args("-").join(" ")));
        } else {
            let input = file.to_string_lossy();
            calls.push(format!("tesseract {}", strips::tesseract_args(&input).join(" ")));
        }
    }
    calls.sort();
    calls.join("\n")
}

#[test]
fn the_plan_and_the_tool_calls_match_the_bash_script() {
    let rows = rows();
    let mut compared = 0;
    for row in rows.iter().filter(|row| !row.name.starts_with("info/")) {
        let (image_w, image_h) = image_of(row);
        let mut lines = vec![window_line(geometry_of(row), (image_w, image_h))];
        lines.extend(strips::plan(image_w, image_h, row.window.0).iter().map(strip_line));
        assert_eq!(lines.join("\n"), row.stream, "{}: stream", row.name);
        assert_eq!(expected_calls(row), row.calls, "{}: calls", row.name);
        compared += 1;
    }
    assert!(compared >= 80, "the grid shrank to {compared} rows");
}

#[test]
fn the_grid_reaches_every_strip_count_and_both_brightnesses() {
    let rows = rows();
    for count in [1, 4, 5, 6] {
        assert!(
            rows.iter()
                .any(|row| row.stream.matches("#strip").count() == count && !row.name.starts_with("info/")),
            "no row with {count} strips"
        );
    }
    assert!(rows.iter().any(|row| row.mean < DARK_BELOW));
    assert!(rows.iter().any(|row| row.mean >= DARK_BELOW));
}

#[test]
fn the_info_line_matches_the_bash_script() {
    let rows = rows();
    let infos: Vec<&Row> = rows.iter().filter(|row| row.name.starts_with("info/")).collect();
    assert_eq!(infos.len(), 2);
    for row in infos {
        let image = image_of(row);
        let info = CaptureInfo {
            class: "term".into(),
            mode: CaptureMode::Toplevel,
            size: row.window,
            image,
            inverted: row.mean < DARK_BELOW,
            strips: strips::plan(image.0, image.1, row.window.0).len(),
            ocr_ms: 0,
        };
        assert_eq!(info.line(), row.calls.replace("ocr_ms=N", "ocr_ms=0"), "{}", row.name);
    }
}

#[test]
fn a_changed_golden_is_a_mismatch() {
    let row = rows().remove(0);
    let mut changed = row.calls.clone();
    changed.push('x');
    assert_ne!(expected_calls(&row), changed);
}
