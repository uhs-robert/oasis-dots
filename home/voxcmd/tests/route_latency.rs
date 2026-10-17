//! the routing latency budget: `explain` without hooks, from process start to exit, p95 under 10 ms (voxcmd-port 0.1, 4.5)
//!
//! Against the TOML fixtures plus the committed `_legacy-dump` of the bash integrations, so no bash starts and no hook
//! runs. A release build only: a debug build is several times slower and says nothing about the budget.
use std::path::Path;
use std::process::Command;
use std::time::Instant;

const RUNS_PER_PHRASE: usize = 20;
const BUDGET_MILLIS: f64 = 10.0;

fn bench_phrases() -> Vec<String> {
    let table = std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/bench-phrases.tsv")).unwrap();
    table
        .lines()
        .skip(1)
        .filter_map(|line| line.split('\t').next())
        .filter(|phrase| !phrase.is_empty())
        .map(str::to_string)
        .collect()
}

#[test]
#[cfg_attr(debug_assertions, ignore = "timing needs a release build: cargo test --release")]
fn explain_without_hooks_stays_under_the_budget() {
    let fixtures = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
    let config = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(config.path().join("integrations")).unwrap();
    for stem in ["media", "apps", "click"] {
        std::fs::copy(
            fixtures.join(format!("integrations/{stem}.toml")),
            config.path().join(format!("integrations/{stem}.toml")),
        )
        .unwrap();
    }
    let explain = |phrase: &str| {
        let started = Instant::now();
        let output = Command::new(env!("CARGO_BIN_EXE_voxcmd"))
            .args(["explain", "--", phrase])
            .env_clear()
            .env("HOME", "/nonexistent")
            .env("TZ", "America/New_York")
            .env("VOXCMD_CONFIG_DIR", config.path())
            .env("VOXCMD_LEGACY_DUMP_FILE", fixtures.join("legacy-dump.jsonl"))
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{phrase}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        started.elapsed().as_secs_f64() * 1000.0
    };
    let mut samples = Vec::new();
    for phrase in bench_phrases() {
        explain(&phrase);
        samples.extend((0..RUNS_PER_PHRASE).map(|_| explain(&phrase)));
    }
    samples.sort_by(f64::total_cmp);
    let p50 = samples[samples.len() / 2];
    let p95 = samples[samples.len() * 95 / 100];
    println!(
        "explain without hooks over {} runs: p50 {p50:.2} ms, p95 {p95:.2} ms",
        samples.len()
    );
    assert!(
        p95 < BUDGET_MILLIS,
        "p95 {p95:.2} ms is over the {BUDGET_MILLIS} ms budget"
    );
}
