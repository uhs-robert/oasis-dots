//! `voxcmd util speech|voice-env` against what the bash helpers printed for the same inputs (golden files in
//! tests/fixtures, frozen; the generator is gone). A failure here means the Rust binary no longer behaves like the bash it replaces.
use std::path::{Path, PathBuf};
use std::process::Command;

fn fixtures_dir() -> PathBuf {
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

fn arguments(operation: &str, input: &str) -> Vec<String> {
    let (subcommand, flags): (&[&str], &[&str]) = match operation {
        "parse-time" => (&["util", "speech", "parse-time"], &[]),
        "parse-time-today" => (&["util", "speech", "parse-time"], &["--today"]),
        "parse-duration" | "split-duration" | "parse-day" | "format-at" | "format-due" | "format-length" => {
            (&["util", "speech", operation], &[])
        }
        "voice-env" => (&["util", "voice-env"], &[]),
        other => panic!("unknown golden operation {other}"),
    };
    let mut args: Vec<String> = subcommand.iter().chain(flags).map(|s| s.to_string()).collect();
    args.push("--".to_string());
    args.push(input.to_string());
    args
}

/// Runs one golden row; Some(description) when the binary disagrees with bash.
fn mismatch(fixtures: &Path, line: &str) -> Option<String> {
    let fields: Vec<&str> = line.splitn(5, '\t').collect();
    let [env, operation, input, status, expected] = fields[..] else {
        panic!("malformed golden row: {line:?}")
    };
    let input = unescape(input);
    let expected = unescape(expected);
    let mut command = Command::new(env!("CARGO_BIN_EXE_voxcmd"));
    command
        .env_clear()
        .env("PATH", std::env::var_os("PATH").unwrap_or_default())
        .env("HOME", "/nonexistent")
        .env("TZ", "America/New_York")
        .env("LC_ALL", "C");
    for pair in env.split(' ').filter(|pair| *pair != "-") {
        let (name, value) = pair.split_once('=').expect("KEY=VALUE");
        let value = value
            .strip_prefix('@')
            .map_or(value.to_string(), |path| fixtures.join(path).display().to_string());
        command.env(name, value);
    }
    let output = command
        .args(arguments(operation, &input))
        .output()
        .expect("the binary runs");
    let got_status = output.status.code().unwrap_or(-1).to_string();
    let got = String::from_utf8_lossy(&output.stdout)
        .trim_end_matches('\n')
        .to_string();
    (got_status != status || got != expected).then(|| {
        format!("{operation} {input:?} [{env}]: bash exit {status} {expected:?}, rust exit {got_status} {got:?}")
    })
}

#[test]
fn rust_matches_the_bash_goldens() {
    let fixtures = fixtures_dir();
    let goldens = std::fs::read_to_string(fixtures.join("speech-goldens.tsv"))
        .expect("the golden file is missing; goldens are frozen, restore it from git");
    let rows: Vec<&str> = goldens.lines().collect();
    assert!(
        rows.len() > 1000,
        "only {} golden rows: was the corpus lost?",
        rows.len()
    );
    // One process per row; spread over the cores.
    let threads = std::thread::available_parallelism().map_or(4, |count| count.get());
    let mismatches: Vec<String> = std::thread::scope(|scope| {
        let workers: Vec<_> = rows
            .chunks(rows.len().div_ceil(threads))
            .map(|chunk| {
                let fixtures = &fixtures;
                scope.spawn(move || {
                    chunk
                        .iter()
                        .filter_map(|line| mismatch(fixtures, line))
                        .collect::<Vec<_>>()
                })
            })
            .collect();
        workers.into_iter().flat_map(|worker| worker.join().unwrap()).collect()
    });
    assert!(
        mismatches.is_empty(),
        "{} of {} rows differ:\n{}",
        mismatches.len(),
        rows.len(),
        mismatches[..mismatches.len().min(40)].join("\n")
    );
}
