//! `voxcmd internal click-match` as run.sh calls it: the awk's interface (target in the
//! environment, page on stdin, candidates on stdout, trace on stderr, exit 2 where the awk dies). The matching itself is
//! compared with the awk in src/click/goldens.rs.
use std::io::Write;
use std::process::{Command, Output, Stdio};

fn click_match(target: &str, flags: &[&str], page: &str) -> Output {
    let mut child = Command::new(env!("CARGO_BIN_EXE_voxcmd"))
        .args(["internal", "click-match"])
        .args(flags)
        .env("CLICK_TARGET", target)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(page.as_bytes()).unwrap();
    child.wait_with_output().unwrap()
}

const PAGE: &str = "#window 100 50 160 96 256 154\n#strip 0 0 0 154\n\
5\t1\t1\t1\t1\t1\t80\t40\t48\t24\t95\tSign\n5\t1\t1\t1\t1\t2\t136\t40\t24\t24\t95\tin\n";

#[test]
fn candidates_go_to_stdout_one_per_line() {
    let output = click_match("sign in", &[], PAGE);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(
        String::from_utf8_lossy(&output.stdout),
        "175\t82\tsign\tSign in - middle\t150\t75\t50\t15\n"
    );
    assert!(output.stderr.is_empty());
}

#[test]
fn the_trace_goes_to_stderr_and_stdout_is_unchanged() {
    let plain = click_match("sign in", &[], PAGE);
    let explained = click_match("sign in", &["--explain"], PAGE);
    assert_eq!(plain.stdout, explained.stdout);
    let trace = String::from_utf8_lossy(&explained.stderr);
    assert_eq!(
        trace.lines().collect::<Vec<_>>(),
        [
            "~pass\twhole",
            "~cand\t1\t175\t82\tword\tsign",
            "~run\t1\tsign(95) in(95)\t1 candidate"
        ]
    );
}

#[test]
fn spans_searches_inside_a_sentence() {
    let page = PAGE.replace("Sign", "Please").replace("\tin\n", "\tsign\n");
    assert!(click_match("sign", &[], &page).stdout.len() > 1);
    let output = click_match("sign", &["--spans", "--explain"], &page);
    assert!(String::from_utf8_lossy(&output.stderr).starts_with("~pass\tspans\n"));
    assert!(
        String::from_utf8_lossy(&output.stdout).starts_with("193\t82\tsign\tPlease sign - middle\t185\t75\t15\t15")
    );
}

#[test]
fn a_filler_only_target_prints_nothing_and_still_traces_its_pass() {
    let output = click_match("the", &["--explain"], PAGE);
    assert_eq!(output.status.code(), Some(0));
    assert!(output.stdout.is_empty());
    assert_eq!(String::from_utf8_lossy(&output.stderr), "~pass\twhole\n");
}

#[test]
fn a_zero_image_size_fails_with_status_2_and_no_candidates() {
    let output = click_match("sign in", &[], &PAGE.replace("256 154", "0 154"));
    assert_eq!(output.status.code(), Some(2));
    assert!(output.stdout.is_empty());
    assert!(String::from_utf8_lossy(&output.stderr).contains("division by zero attempted"));
}

#[test]
fn a_backslash_in_the_target_is_kept() {
    let output = click_match("sign\\in", &[], PAGE);
    assert_eq!(output.status.code(), Some(0));
    assert!(!output.stdout.is_empty());
}

/// Pins the known divergence from the awk (see `click_match` in src/click/internal.rs): invalid bytes become U+FFFD
/// before the 48-character label cut, where gawk keeps the bytes.
#[test]
fn invalid_utf8_becomes_replacement_characters_before_the_label_is_cut() {
    let mut page = b"#window 100 50 160 96 256 154\n#strip 0 0 0 154\n5\t1\t1\t1\t1\t1\t80\t40\t48\t24\t95\t".to_vec();
    page.extend(b"a\xff".repeat(30));
    page.push(b'\n');
    let mut child = Command::new(env!("CARGO_BIN_EXE_voxcmd"))
        .args(["internal", "click-match"])
        .env("CLICK_TARGET", "aaaa")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(&page).unwrap();
    let output = child.wait_with_output().unwrap();
    let stdout = String::from_utf8(output.stdout).expect("output is valid UTF-8");
    let label = stdout.lines().next().unwrap().split('\t').nth(3).unwrap();
    assert_eq!(label, format!("{}a... - middle #1", "a\u{fffd}".repeat(22)));
}
