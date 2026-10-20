//! The click integration end to end with real child processes: `screen_text`'s lookup, the covering check, the
//! window-changed check between the capture and the click, and the clicks. The tools are stubs on a PATH of their own;
//! `hyprctl` answers from files a test rewrites, so a test can move, close or refocus the window at any point.
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const DEFAULT_WINDOW: &str = r#"{"address": "0x2001", "at": [100, 50], "size": [160, 96], "monitor": 0, "stableId": "18000004", "floating": false, "pinned": false, "workspace": {"id": 1}}"#;
const DEFAULT_MONITORS: &str = r#"[{"id": 0, "name": "DP-1", "width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": [0, 0, 0, 0]}]"#;
const HEADER: &str = "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext";

/// The window is 160x96 logical, captured at 256x154 (scale 1.6). "Sign in" is centred at 175,82 and "Settings" at
/// 230,132 on the screen.
const SIGN_IN_AND_SETTINGS: &[&str] = &[
    "5\t1\t1\t1\t1\t1\t80\t40\t48\t24\t95\tSign",
    "5\t1\t1\t1\t1\t2\t136\t40\t24\t24\t95\tin",
    "5\t1\t2\t1\t1\t1\t160\t120\t96\t24\t95\tSettings",
];

struct Rig {
    root: tempfile::TempDir,
}

impl Rig {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        for dir in ["config/integrations", "runtime", "bin", "work"] {
            std::fs::create_dir_all(root.path().join(dir)).unwrap();
        }
        let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/integrations/click.toml");
        std::fs::copy(fixture, root.path().join("config/integrations/click.toml")).unwrap();
        let rig = Self { root };
        // Every tool logs its argv, one line a call, to work/calls.
        let log = "printf '%s' \"${0##*/}\" >> \"$WORK/calls\"; for arg; do printf ' %s' \"$arg\" >> \"$WORK/calls\"; done; echo >> \"$WORK/calls\"";
        rig.script(
            "hyprctl",
            &format!(
                "case \"$1\" in\n\
                 activewindow|clients|monitors) cat \"$WORK/$1.json\" ;;\n\
                 dispatch) {log}; cat \"$WORK/dispatch-answer\" 2>/dev/null || echo ok ;;\n\
                 *) exit 1 ;;\nesac"
            ),
        );
        rig.script(
            "grim",
            &format!(
                "{log}\nfor out; do :; done\n{{ printf 'P6\\n256 154\\n255\\n'; head -c 118272 /dev/zero; }} > \"$out\""
            ),
        );
        rig.script(
            "magick",
            "previous=\nfor arg; do\n  [ \"$previous\" != -write ] || case \"$arg\" in info:-) echo 1 ;; *) : > \"$arg\" ;; esac\n  previous=$arg\ndone",
        );
        // The user changes the focus while the page is being read: the window the click then finds is not the one
        // that was captured.
        rig.script(
            "tesseract",
            "echo run >> \"$WORK/ocr-runs\"\n[ ! -f \"$WORK/switch-during-ocr\" ] || cp \"$WORK/switch-during-ocr\" \"$WORK/activewindow.json\"\ncat \"$WORK/tsv\"",
        );
        rig.script(
            "wlrctl",
            &format!("{log}; if [ -f \"$WORK/wlrctl-fails\" ]; then cat \"$WORK/wlrctl-fails\" >&2; exit 1; fi"),
        );
        rig.script("notify-send", log);
        rig.script("setsid", log);
        rig.set("activewindow.json", DEFAULT_WINDOW);
        rig.set("clients.json", "[]");
        rig.set("monitors.json", DEFAULT_MONITORS);
        rig.screen(SIGN_IN_AND_SETTINGS);
        rig
    }

    fn path(&self) -> &Path {
        self.root.path()
    }

    fn work(&self) -> PathBuf {
        self.path().join("work")
    }

    fn set(&self, name: &str, text: &str) {
        std::fs::write(self.work().join(name), text).unwrap();
    }

    fn screen(&self, rows: &[&str]) {
        self.set("tsv", &format!("{HEADER}\n{}\n", rows.join("\n")));
    }

    fn calls(&self) -> Vec<String> {
        std::fs::read_to_string(self.work().join("calls"))
            .unwrap_or_default()
            .lines()
            .map(str::to_string)
            .collect()
    }

    fn forget_calls(&self) {
        let _ = std::fs::remove_file(self.work().join("calls"));
    }

    /// Calls to the tool, with its name.
    fn calls_of(&self, tool: &str) -> Vec<String> {
        self.calls()
            .into_iter()
            .filter(|call| call.split(' ').next() == Some(tool))
            .collect()
    }

    fn script(&self, name: &str, body: &str) {
        let temp = self.path().join("bin").join(format!(".{name}.tmp"));
        std::fs::write(
            &temp,
            format!("#!/bin/sh\n[ -z \"$VOXCMD_TEST_PROBE\" ] || exit 0\n{body}\n"),
        )
        .unwrap();
        std::fs::set_permissions(&temp, std::fs::Permissions::from_mode(0o755)).unwrap();
        let path = self.path().join("bin").join(name);
        std::fs::rename(&temp, &path).unwrap();
        settle_exec(&path);
    }

    fn command(&self, args: &[&str]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_voxcmd"));
        command
            .args(args)
            .env_clear()
            .env("PATH", format!("{}/bin:/usr/bin:/bin", self.path().display()))
            .env("HOME", "/nonexistent")
            .env("LC_ALL", "C")
            .env("WORK", self.work())
            .env("VOXCMD_CONFIG_DIR", self.path().join("config"))
            .env("XDG_RUNTIME_DIR", self.path().join("runtime"))
            .env("XDG_STATE_HOME", self.path().join("state"))
            .env("XDG_CONFIG_HOME", self.path().join("xdg"))
            .env("VOXCMD_TIME_SCALE", "0.1");
        command
    }

    fn explain(&self, phrase: &str) -> String {
        text(&self.command(&["explain", phrase]).output().unwrap())
    }

    fn run(&self, phrase: &str) -> Output {
        self.command(&["run", phrase]).output().unwrap()
    }

    /// `internal click-at` for a candidate id: its stdout (the failure reason) and exit code.
    fn click_at(&self, id: &str) -> (String, Option<i32>) {
        let output = self
            .command(&["internal", "click-at", "--target", "sign in", id])
            .output()
            .unwrap();
        (
            String::from_utf8_lossy(&output.stdout).trim_end().to_string(),
            output.status.code(),
        )
    }

    fn target_file(&self) -> PathBuf {
        self.path().join("runtime/voxcmd/click-target")
    }

    fn toasts(&self) -> Vec<String> {
        self.calls_of("notify-send")
    }

    fn moved(&self) -> bool {
        self.calls().iter().any(|call| call.starts_with("hyprctl dispatch"))
    }
}

fn text(output: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    )
}

/// Runs the script once in probe mode until it execs; see tests/run.rs.
fn settle_exec(path: &Path) {
    for _ in 0..500 {
        match Command::new(path).env("VOXCMD_TEST_PROBE", "1").status() {
            Err(error) if error.kind() == std::io::ErrorKind::ExecutableFileBusy => {
                std::thread::sleep(std::time::Duration::from_millis(10));
            }
            _ => return,
        }
    }
}

fn client(address: &str, at: [i64; 2], size: [i64; 2], floating: bool, pinned: bool, workspace: i64) -> String {
    format!(
        r#"{{"address": "{address}", "at": [{}, {}], "size": [{}, {}], "floating": {floating}, "pinned": {pinned}, "workspace": {{"id": {workspace}}}, "mapped": true, "hidden": false}}"#,
        at[0], at[1], size[0], size[1]
    )
}

/// The point the explain's single run option clicks, "covered" when that option says so, or "-".
fn runs_at(explain: &str) -> String {
    for line in explain.lines().filter(|line| line.starts_with("option 1: ")) {
        if line.contains("id='covered:'") {
            return "covered".to_string();
        }
        if let Some(start) = line.find("id='") {
            let id = &line[start + 4..];
            let point: Vec<&str> = id.split(',').take(2).collect();
            if point.len() == 2 {
                return point.join(",");
            }
        }
    }
    "-".to_string()
}

const DEFAULT_ID: &str = "175,82,left,80,40,48,24";

// ---- the lookup ----

#[test]
fn a_dry_run_route_reads_the_screen_and_records_the_window_for_the_click() {
    let rig = Rig::new();
    let out = rig.explain("click sign in");
    assert_eq!(runs_at(&out), "175,82", "{out}");
    assert!(out.contains("action=click "), "{out}");
    // explain is the dry run, and it still writes the record the click checks.
    let record: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(rig.target_file()).unwrap()).unwrap();
    assert_eq!(record["window"]["stableId"], "18000004");
    assert!(
        !rig.moved() && rig.calls_of("wlrctl").is_empty() && rig.toasts().is_empty(),
        "{:?}",
        rig.calls()
    );
}

#[test]
fn a_target_of_only_filler_or_ignored_words_never_reads_the_screen() {
    let rig = Rig::new();
    for phrase in ["click left", "click it", "click here", "right click"] {
        let out = rig.explain(phrase);
        assert!(out.contains("result:      no match"), "{phrase}: {out}");
    }
    assert!(rig.calls_of("grim").is_empty());
    assert!(!rig.target_file().exists());
}

#[test]
fn text_that_is_nowhere_on_screen_is_reported_not_handed_on() {
    let rig = Rig::new();
    let out = rig.explain("click nowhere to be found");
    assert!(out.contains("action=no_text"), "{out}");
}

#[test]
fn no_focused_window_is_an_error_candidate_whose_label_is_the_reason() {
    let rig = Rig::new();
    rig.set("activewindow.json", "{}");
    let out = rig.explain("click sign in");
    assert!(out.contains("label='no focused window'"), "{out}");
    assert!(out.contains("id='error:no focused window'"), "{out}");
}

// ---- covering ----

#[test]
fn a_window_over_a_candidate_covers_it_and_the_others_stay() {
    let rig = Rig::new();
    let over = client("0x3001", [150, 50], [60, 60], true, false, 1);
    rig.set(
        "clients.json",
        &format!("[{}, {over}]", client("0x2001", [100, 50], [160, 96], false, false, 1)),
    );
    assert_eq!(runs_at(&rig.explain("click sign in")), "covered");
    assert_eq!(runs_at(&rig.explain("click settings")), "230,132");
    let out = rig.explain("click sign in");
    assert!(
        out.contains("action=click ") && !out.contains("no_text"),
        "all covered is not 'not on screen': {out}"
    );
}

#[test]
fn a_tiled_window_beside_another_workspace_unmapped_and_hidden_windows_cover_nothing() {
    let rig = Rig::new();
    let set = |others: &[String]| {
        let mut all = vec![client("0x2001", [100, 50], [160, 96], false, false, 1)];
        all.extend(others.iter().cloned());
        rig.set("clients.json", &format!("[{}]", all.join(", ")));
        runs_at(&rig.explain("click sign in"))
    };
    assert_eq!(set(&[client("0x3001", [150, 50], [60, 60], false, false, 1)]), "175,82");
    assert_eq!(set(&[client("0x3001", [150, 50], [60, 60], true, false, 2)]), "175,82");
    assert_eq!(
        set(&[client("0x3001", [150, 50], [60, 60], true, false, 1).replace("\"mapped\": true", "\"mapped\": false")]),
        "175,82"
    );
    assert_eq!(
        set(&[client("0x3001", [150, 50], [60, 60], true, false, 1).replace("\"hidden\": false", "\"hidden\": true")]),
        "175,82"
    );
    assert_eq!(
        set(&[client("0x3001", [150, 50], [60, 60], true, true, 2)]),
        "covered",
        "pinned covers from any workspace"
    );
}

#[test]
fn a_reserved_edge_the_bar_covers_a_candidate_in_it_like_a_window_does() {
    let rig = Rig::new();
    let monitors = |reserved: &str| {
        format!(
            r#"[{{"id": 0, "width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": {reserved}}}]"#
        )
    };
    rig.set("monitors.json", &monitors("[0, 100, 0, 0]"));
    assert_eq!(runs_at(&rig.explain("click sign in")), "covered");
    assert_eq!(runs_at(&rig.explain("click settings")), "230,132", "below the bar");
    rig.set("monitors.json", &monitors("[200, 0, 0, 0]"));
    assert_eq!(runs_at(&rig.explain("click sign in")), "covered");
    rig.set("monitors.json", &monitors("[0, 0, 0, 0]"));
    assert_eq!(runs_at(&rig.explain("click sign in")), "175,82");
}

#[test]
fn a_bar_on_another_monitor_covers_only_what_is_on_that_monitor() {
    let rig = Rig::new();
    let both = r#"[
        {"id": 0, "name": "DP-1", "width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": [0, 0, 0, 0]},
        {"id": 1, "name": "DP-2", "width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 1920, "y": 0, "reserved": [0, 100, 0, 0]}]"#;
    rig.set("monitors.json", both);
    assert_eq!(
        runs_at(&rig.explain("click sign in")),
        "175,82",
        "the window is on the first monitor"
    );
    // The same window on the second monitor, under that monitor's bar (offset 1920).
    rig.set(
        "activewindow.json",
        &DEFAULT_WINDOW
            .replace("[100, 50]", "[2020, 50]")
            .replace("\"monitor\": 0", "\"monitor\": 1"),
    );
    assert_eq!(runs_at(&rig.explain("click sign in")), "covered");
    assert_eq!(
        runs_at(&rig.explain("click settings")),
        "2150,132",
        "Settings is below the bar, in global coordinates"
    );
}

// ---- the click ----

#[test]
fn a_click_moves_the_pointer_then_clicks_the_button_the_phrase_named() {
    let rig = Rig::new();
    let output = rig.run("right click sign in");
    assert_eq!(output.status.code(), Some(0), "{}", text(&output));
    assert_eq!(
        rig.calls()
            .into_iter()
            .filter(|call| !call.starts_with("grim") && !call.starts_with("magick"))
            .collect::<Vec<_>>(),
        [
            "hyprctl dispatch hl.dsp.cursor.move({x=175,y=82})",
            "wlrctl pointer click right"
        ]
    );
    assert!(rig.toasts().is_empty(), "click is silent");
}

#[test]
fn a_double_and_a_triple_click_are_two_and_three_left_clicks() {
    let rig = Rig::new();
    rig.run("double click sign in");
    assert_eq!(rig.calls_of("wlrctl"), ["wlrctl pointer click left"; 2]);
    rig.forget_calls();
    rig.run("triple click sign in");
    assert_eq!(rig.calls_of("wlrctl"), ["wlrctl pointer click left"; 3]);
}

#[test]
fn a_failed_click_is_one_error_toast_with_the_tools_reason_and_no_screen_text() {
    let rig = Rig::new();
    rig.set("wlrctl-fails", "wlrctl: no seat");
    let output = rig.run("click sign in");
    assert_eq!(output.status.code(), Some(1), "{}", text(&output));
    let toasts = rig.toasts();
    assert_eq!(toasts.len(), 1, "{toasts:?}");
    assert_eq!(
        toasts[0],
        "notify-send -a voxcmd voxcmd failed Click: click: wlrctl: no seat"
    );
}

#[test]
fn a_double_click_stops_at_the_first_failing_click() {
    let rig = Rig::new();
    rig.set("wlrctl-fails", "wlrctl: no seat");
    let (reason, code) = {
        rig.explain("click sign in");
        rig.click_at("175,82,double,1,2,3,4")
    };
    assert_eq!((reason.as_str(), code), ("wlrctl: no seat", Some(1)));
    assert_eq!(rig.calls_of("wlrctl").len(), 1);
}

#[test]
fn a_pointer_move_that_is_not_ok_fails_with_the_last_line_of_its_answer() {
    let rig = Rig::new();
    rig.explain("click sign in");
    rig.set("dispatch-answer", "first\nno such dispatcher");
    let (reason, code) = rig.click_at(DEFAULT_ID);
    assert_eq!((reason.as_str(), code), ("no such dispatcher", Some(1)));
    assert!(rig.calls_of("wlrctl").is_empty(), "no click after a failed move");
}

#[test]
fn the_failure_sentinels_report_their_reason_or_say_what_is_covered() {
    let rig = Rig::new();
    let (reason, code) = rig.click_at("error:no focused window");
    assert_eq!((reason.as_str(), code), ("no focused window", Some(1)));
    let (reason, code) = rig.click_at("covered:");
    assert_eq!((reason.as_str(), code), ("", Some(0)));
    assert_eq!(
        rig.toasts(),
        [r#"notify-send --transient --app-name=voxcmd "sign in" is covered by another window"#]
    );
    assert!(!rig.moved());
}

#[test]
fn a_negative_coordinate_from_a_monitor_left_of_the_origin_clicks_where_it_says() {
    let rig = Rig::new();
    rig.set("activewindow.json", &DEFAULT_WINDOW.replace("[100, 50]", "[-1820, 50]"));
    let out = rig.explain("click sign in");
    assert_eq!(runs_at(&out), "-1745,82", "{out}");
    let (_, code) = rig.click_at("-1745,82,left,-1820,50,48,24");
    assert_eq!(code, Some(0));
    assert!(
        rig.calls()
            .contains(&"hyprctl dispatch hl.dsp.cursor.move({x=-1745,y=82})".to_string()),
        "{:?}",
        rig.calls()
    );
}

// ---- the window changed between the capture and the click ----

fn assert_not_clicked(rig: &Rig, why: &str) {
    assert_eq!(
        rig.toasts(),
        ["notify-send --transient --app-name=voxcmd The window changed; say it again"],
        "{why}"
    );
    assert!(
        !rig.moved() && rig.calls_of("wlrctl").is_empty(),
        "{why}: {:?}",
        rig.calls()
    );
}

#[test]
fn the_window_that_was_captured_still_there_is_clicked() {
    let rig = Rig::new();
    rig.explain("click sign in");
    rig.forget_calls();
    assert_eq!(rig.click_at(DEFAULT_ID).1, Some(0));
    assert!(rig.toasts().is_empty());
    assert_eq!(rig.calls_of("wlrctl"), ["wlrctl pointer click left"]);
}

#[test]
fn a_window_that_moved_resized_closed_or_lost_the_focus_is_not_clicked() {
    let cases = [
        ("moved", DEFAULT_WINDOW.replace("[100, 50]", "[300, 50]")),
        ("resized", DEFAULT_WINDOW.replace("[160, 96]", "[400, 96]")),
        ("closed (nothing focused)", "{}".to_string()),
        (
            "focus moved to another window",
            DEFAULT_WINDOW
                .replace("0x2001", "0x3001")
                .replace("18000004", "18000009"),
        ),
    ];
    for (why, now) in cases {
        let rig = Rig::new();
        rig.explain("click sign in");
        rig.forget_calls();
        rig.set("activewindow.json", &now);
        let (reason, code) = rig.click_at(DEFAULT_ID);
        assert_eq!((reason.as_str(), code), ("", Some(0)), "{why}");
        assert_not_clicked(&rig, why);
    }
}

#[test]
fn the_window_changing_while_the_page_is_read_stops_the_click_of_the_same_run() {
    // The record is written when the shot is taken, before OCR; the focus then moves during OCR, and the click that
    // follows in the same run must find out.
    let rig = Rig::new();
    rig.set(
        "switch-during-ocr",
        &DEFAULT_WINDOW
            .replace("0x2001", "0x3001")
            .replace("18000004", "18000009"),
    );
    let output = rig.run("click sign in");
    assert_eq!(output.status.code(), Some(0), "{}", text(&output));
    assert_not_clicked(&rig, "focus moved during OCR");
}

#[test]
fn a_window_moved_while_the_page_is_read_stops_the_click_of_the_same_run() {
    let rig = Rig::new();
    rig.set("switch-during-ocr", &DEFAULT_WINDOW.replace("[100, 50]", "[130, 50]"));
    rig.run("click sign in");
    assert_not_clicked(&rig, "window moved during OCR");
}

#[test]
fn a_record_older_than_a_minute_or_missing_is_not_trusted() {
    let rig = Rig::new();
    rig.explain("click sign in");
    let mut record: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(rig.target_file()).unwrap()).unwrap();
    let captured_at = record["captured_at"].as_i64().unwrap();
    // 59 s old is still trusted, 61 s is not; the limit itself is unit-tested.
    record["captured_at"] = (captured_at - 59).into();
    std::fs::write(rig.target_file(), record.to_string()).unwrap();
    rig.forget_calls();
    assert_eq!(rig.click_at(DEFAULT_ID).1, Some(0));
    assert!(rig.toasts().is_empty(), "{:?}", rig.toasts());
    record["captured_at"] = (captured_at - 61).into();
    std::fs::write(rig.target_file(), record.to_string()).unwrap();
    rig.forget_calls();
    rig.click_at(DEFAULT_ID);
    assert_not_clicked(&rig, "61 s old");
    std::fs::remove_file(rig.target_file()).unwrap();
    rig.forget_calls();
    rig.click_at(DEFAULT_ID);
    assert_not_clicked(&rig, "no record");
}

#[test]
fn the_record_is_private_and_leaves_no_half_written_copy() {
    use std::os::unix::fs::MetadataExt;
    let rig = Rig::new();
    rig.explain("click sign in");
    let dir = rig.path().join("runtime/voxcmd");
    assert_eq!(std::fs::metadata(&dir).unwrap().mode() & 0o777, 0o700);
    let stray: Vec<_> = std::fs::read_dir(&dir)
        .unwrap()
        .filter_map(|entry| entry.ok()?.file_name().into_string().ok())
        .filter(|name| name.starts_with("click-target."))
        .collect();
    assert!(stray.is_empty(), "{stray:?}");
}

// ---- the numbered boxes ----

#[test]
fn several_matches_ask_through_the_hints_overlay_with_each_options_box_and_the_answer_clicks_that_one() {
    let rig = Rig::new();
    rig.screen(&[
        "5\t1\t1\t1\t1\t1\t80\t40\t48\t24\t95\tNext",
        "5\t1\t2\t1\t1\t1\t160\t120\t96\t24\t95\tNext",
    ]);
    // The asker is given the kind first, as `ask hints <label> <choices>`; it answers the second choice.
    rig.script("ask", "printf '%s\\n' \"$*\" >> \"$WORK/asked\"\necho 1");
    let output = rig
        .command(&["run", "click next"])
        .env("VOXCMD_ASK_CMD", rig.path().join("bin/ask"))
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(0), "{}", text(&output));
    let asked = std::fs::read_to_string(rig.work().join("asked")).unwrap();
    assert!(asked.starts_with("hints Which one? [{"), "{asked}");
    // The window is at 100,50 and read at scale 1.6: each box is the word's, in global logical pixels.
    assert_eq!(
        asked,
        "hints Which one? [{\"box\":[150,75,30,15],\"id\":\"0\",\"label\":\"Click: click Next - middle\"},\
         {\"box\":[200,125,60,15],\"id\":\"1\",\"label\":\"Click: click Next - bottom right\"}]\n"
    );
    // Answer 1 is the second option: the one lower on the screen.
    let moved: Vec<_> = rig
        .calls()
        .into_iter()
        .filter(|call| call.starts_with("hyprctl dispatch"))
        .collect();
    assert_eq!(moved.len(), 1, "{:?}", rig.calls());
    assert_eq!(moved, ["hyprctl dispatch hl.dsp.cursor.move({x=230,y=132})"]);
}

#[test]
fn show_hints_is_not_a_built_in_in_a_toml_integration_and_runs_its_command() {
    let rig = Rig::new();
    rig.run("show hints");
    assert_eq!(
        rig.calls_of("setsid"),
        ["setsid -f wl-kbptr -o modes=floating,click -o mode_floating.source=detect"]
    );
}

// ---- the bridge: the shipped click.sh is served by the built-ins, a user's own copy is not ----

/// A bash config holding click.sh (edited by `edit`, given the file's text) and a stand-in for the bash voxcmd that
/// logs every call it gets before running the real one. Returns the log's path with a command builder for it.
struct Bridged {
    rig: Rig,
    log: PathBuf,
}

impl Bridged {
    fn new(edit: impl Fn(String) -> String) -> Self {
        let rig = Rig::new();
        let package = Path::new(env!("CARGO_MANIFEST_DIR"));
        let config = rig.path().join("config-bash");
        std::fs::create_dir_all(config.join("integrations.d")).unwrap();
        let shipped = std::fs::read_to_string(package.join(".config/voxcmd/integrations.d/click.sh")).unwrap();
        let edited = edit(shipped.clone());
        std::fs::write(config.join("integrations.d/click.sh"), &edited).unwrap();
        let log = rig.path().join("legacy.log");
        rig.script(
            "legacy-voxcmd",
            &format!(
                "echo \"$*\" >> '{}'\nexec '{}' \"$@\"",
                log.display(),
                package.join(".local/bin/voxcmd").display()
            ),
        );
        Self { rig, log }
    }

    fn command(&self, args: &[&str]) -> Command {
        let mut command = self.rig.command(args);
        command
            .env("VOXCMD_CONFIG_DIR", self.rig.path().join("config-bash"))
            .env("VOXCMD_LEGACY_BIN", self.rig.path().join("bin/legacy-voxcmd"))
            .env("XDG_CACHE_HOME", self.rig.path().join("cache"));
        command
    }

    fn explain(&self, phrase: &str) -> String {
        text(&self.command(&["explain", phrase]).output().unwrap())
    }

    /// The calls the bash voxcmd got that name click.sh.
    fn click_sh_calls(&self) -> Vec<String> {
        std::fs::read_to_string(&self.log)
            .unwrap_or_default()
            .lines()
            .filter(|line| line.starts_with("_legacy-hook") && line.contains("/click.sh"))
            .map(str::to_string)
            .collect()
    }

    fn calls_to_bash(&self) -> Vec<String> {
        std::fs::read_to_string(&self.log)
            .unwrap_or_default()
            .lines()
            .map(str::to_string)
            .collect()
    }
}

#[test]
fn the_shipped_click_sh_is_served_by_the_built_ins_without_a_call_to_its_functions() {
    let bridged = Bridged::new(|text| text);
    let out = bridged.explain("click sign in");
    assert_eq!(runs_at(&out), "175,82", "{out}");
    // The positive control: the bridge was reached for the dump, so the wrapper works.
    assert!(
        bridged.calls_to_bash().iter().any(|call| call == "_legacy-dump"),
        "{:?}",
        bridged.calls_to_bash()
    );
    assert_eq!(
        bridged.click_sh_calls(),
        Vec::<String>::new(),
        "click.sh's hooks were called"
    );
    let output = bridged.command(&["run", "right click sign in"]).output().unwrap();
    assert_eq!(output.status.code(), Some(0), "{}", text(&output));
    assert_eq!(
        bridged.click_sh_calls(),
        Vec::<String>::new(),
        "click.sh's action was called"
    );
    assert_eq!(bridged.rig.calls_of("wlrctl"), ["wlrctl pointer click right"]);
}

#[test]
fn the_shipped_click_sh_routes_no_text_and_show_hints_without_the_bridge_too() {
    let bridged = Bridged::new(|text| text);
    let output = bridged.command(&["run", "click nowhere to be found"]).output().unwrap();
    assert_eq!(output.status.code(), Some(0), "{}", text(&output));
    assert_eq!(
        bridged.rig.toasts(),
        [r#"notify-send --transient --app-name=voxcmd No "nowhere to be found" on screen"#]
    );
    bridged.command(&["run", "show hints"]).output().unwrap();
    assert_eq!(
        bridged.rig.calls_of("setsid"),
        ["setsid -f wl-kbptr -o modes=floating,click -o mode_floating.source=detect"]
    );
    assert_eq!(bridged.click_sh_calls(), Vec::<String>::new());
}

#[test]
fn a_click_sh_with_an_edited_click_command_stays_on_the_bridge() {
    let bridged = Bridged::new(|text| {
        let shipped = "[click]='click_at \"$id\"'";
        assert!(text.contains(shipped), "click.sh changed shape; update this test");
        text.replace(shipped, "[click]='click_at \"$id\" && true'")
    });
    let out = bridged.explain("click sign in");
    assert_eq!(runs_at(&out), "175,82", "{out}");
    let calls = bridged.click_sh_calls();
    assert!(
        calls
            .iter()
            .any(|call| call.starts_with("_legacy-hook candidates ") && call.ends_with(" click sign in")),
        "the edited file's candidates() must be asked: {calls:?}"
    );
}

// ---- explain --window ----

impl Rig {
    /// `explain --window <window> <phrase>`: the output and the exit code.
    fn explain_window(&self, window: &str, phrase: &str) -> (String, Option<i32>) {
        let output = self.command(&["explain", "--window", window, phrase]).output().unwrap();
        (text(&output), output.status.code())
    }

    fn ocr_runs(&self) -> usize {
        std::fs::read_to_string(self.work().join("ocr-runs")).map_or(0, |runs| runs.lines().count())
    }

    fn grim_calls(&self) -> usize {
        self.calls_of("grim").len()
    }

    fn untouched_by_a_click(&self) -> bool {
        !self.moved() && self.calls_of("wlrctl").is_empty() && self.toasts().is_empty()
    }
}

#[test]
fn the_click_section_follows_the_routing_text_and_shares_its_single_capture() {
    let rig = Rig::new();
    let (out, code) = rig.explain_window("focused", "click sign in");
    assert_eq!(code, Some(0), "{out}");
    let routing = out.find("transcript:  click sign in").expect(&out);
    let window = out.find("\nwindow   ").expect(&out);
    assert!(routing < window, "routing text first: {out}");
    assert!(out.contains("capture  toplevel, image 256x154, scale x1.600 y1.604, not inverted, 1 strip(s), OCR "));
    assert!(
        out.contains("candidate 175,82 \"sign\": kept strong (same words)")
            || out.contains("candidate 175,82 \"sign in\": kept strong (same words)"),
        "{out}"
    );
    assert!(out.contains("\noutcome  click at 175,82"), "{out}");
    // The routing half and the click section read one capture: a second would shoot and read the window again.
    assert_eq!(rig.grim_calls(), 1, "{:?}", rig.calls());
    assert_eq!(rig.ocr_runs(), 1);
    assert!(rig.untouched_by_a_click(), "{:?}", rig.calls());
    assert!(!rig.target_file().exists(), "a trace leaves no click-target");
}

#[test]
fn a_legacy_dump_file_keeps_the_built_in_click_capture_under_the_trace() {
    let rig = Rig::new();
    rig.set("legacy-dump.jsonl", "");
    let mut command = rig.command(&["explain", "--window", "focused", "click sign in"]);
    command.env("VOXCMD_LEGACY_DUMP_FILE", rig.work().join("legacy-dump.jsonl"));
    let out = text(&command.output().unwrap());
    assert!(out.contains("\noutcome  click at 175,82"), "{out}");
    assert_eq!(rig.grim_calls(), 1, "{:?}", rig.calls());
    assert_eq!(rig.ocr_runs(), 1);
}

#[test]
fn the_routing_half_still_runs_under_the_trace_and_agrees_with_it() {
    let rig = Rig::new();
    let (out, _) = rig.explain_window("focused", "click sign in");
    assert_eq!(runs_at(&out), "175,82", "{out}");
    assert!(out.contains("\nwhy:\n"), "{out}");
}

#[test]
fn a_window_by_stable_id_is_captured_by_that_id_and_named() {
    let rig = Rig::new();
    rig.set(
        "clients.json",
        r#"[{"address": "0x4001", "mapped": true, "hidden": false, "class": "other", "stableId": "18000009", "at": [100, 50], "size": [160, 96], "floating": false, "pinned": false, "monitor": 0, "workspace": {"id": 1}}]"#,
    );
    let (out, code) = rig.explain_window("18000009", "click sign in");
    assert_eq!(code, Some(0), "{out}");
    assert!(out.contains("\nwindow   other 160x96\n"), "{out}");
    let grim = rig.calls_of("grim");
    assert_eq!(grim.len(), 1, "{grim:?}");
    assert!(grim[0].contains("-T 18000009"), "{grim:?}");
    assert!(rig.untouched_by_a_click());
}

#[test]
fn an_unknown_window_is_a_section_that_says_so_and_the_routing_text_still_prints() {
    let rig = Rig::new();
    let (out, code) = rig.explain_window("99999", "click sign in");
    assert_eq!(code, Some(0), "{out}");
    assert!(out.contains("transcript:  click sign in"), "{out}");
    assert!(
        out.contains(
            "\ntarget   \"sign in\"\noutcome  capture or OCR failed (no such window); a toast says the click failed"
        ),
        "{out}"
    );
    assert_eq!(rig.grim_calls(), 0);
    assert!(rig.untouched_by_a_click());
}

#[test]
fn no_focused_window_is_the_same_section() {
    let rig = Rig::new();
    rig.set("activewindow.json", "{}");
    let (out, _) = rig.explain_window("focused", "click sign in");
    assert!(out.contains("capture or OCR failed (no focused window)"), "{out}");
}

#[test]
fn an_empty_window_is_a_usage_error_and_reads_nothing() {
    let rig = Rig::new();
    let (out, code) = rig.explain_window("", "click sign in");
    assert_eq!(code, Some(2), "{out}");
    assert!(out.contains("--window"), "{out}");
    assert_eq!(rig.grim_calls(), 0);
    let output = rig.command(&["explain", "--window"]).output().unwrap();
    assert_eq!(output.status.code(), Some(2), "a missing id is a usage error too");
}

#[test]
fn a_filler_only_target_prints_no_capture_and_reads_nothing() {
    let rig = Rig::new();
    let (out, _) = rig.explain_window("focused", "click it");
    assert!(
        out.contains(
            "target   \"it\"\noutcome  filler-only target: the screen is not read, and Keybinds' click binds get it"
        ),
        "{out}"
    );
    assert!(!out.contains("\nwindow   "), "{out}");
    assert_eq!(rig.grim_calls(), 0);
}

#[test]
fn a_phrase_that_never_reached_click_says_so() {
    let rig = Rig::new();
    let (out, code) = rig.explain_window("focused", "banana split");
    assert_eq!(code, Some(0), "{out}");
    assert!(
        out.trim_end()
            .ends_with("click     not reached: the phrase did not route to the Click integration"),
        "{out}"
    );
    assert_eq!(rig.grim_calls(), 0);
}

#[test]
fn a_candidate_under_the_bar_is_kept_by_word_matching_and_dropped_as_covered() {
    let rig = Rig::new();
    rig.set(
        "monitors.json",
        r#"[{"id": 0, "width": 1920, "height": 1080, "scale": 1, "transform": 0, "x": 0, "y": 0, "reserved": [0, 100, 0, 0]}]"#,
    );
    let (out, _) = rig.explain_window("focused", "click sign in");
    assert!(
        out.contains("kept strong (same words), then dropped: covered by a reserved edge (the bar)"),
        "{out}"
    );
    assert!(
        out.contains("\noutcome  covered: every candidate is under another window or a reserved edge"),
        "{out}"
    );
}

#[test]
fn a_sentence_runs_the_sub_span_pass() {
    let rig = Rig::new();
    rig.screen(&[
        "5\t1\t1\t1\t1\t1\t10\t40\t12\t24\t95\t2",
        "5\t1\t1\t1\t1\t2\t26\t40\t40\t24\t95\ttasks",
        "5\t1\t1\t1\t1\t3\t70\t40\t30\t24\t95\tare",
        "5\t1\t1\t1\t1\t4\t104\t40\t60\t24\t95\tflagged",
        "5\t1\t1\t1\t1\t5\t168\t40\t50\t24\t95\ttoday",
        "5\t1\t1\t1\t1\t6\t222\t40\t28\t24\t95\tnow",
    ]);
    let (out, _) = rig.explain_window("focused", "click 2 tasks");
    assert!(out.contains("dropped: coverage under half: 2 of 6"), "{out}");
    assert!(
        out.contains("\npass 2: sub-spans of runs (no whole run was kept by word matching)\n"),
        "{out}"
    );
    assert!(out.contains("sub-span, kept strong"), "{out}");
}

#[test]
fn twelve_equal_weak_matches_keep_ten_and_drop_two_in_the_trace() {
    let rig = Rig::new();
    let rows: Vec<String> = (0..12)
        .flat_map(|index| {
            let top = 2 + index * 12;
            [
                format!("5\t1\t{block}\t1\t1\t1\t80\t{top}\t48\t10\t95\tOpen", block = index + 1),
                format!(
                    "5\t1\t{block}\t1\t1\t2\t136\t{top}\t96\t10\t95\tSettings",
                    block = index + 1
                ),
            ]
        })
        .collect();
    let refs: Vec<&str> = rows.iter().map(String::as_str).collect();
    rig.screen(&refs);
    let (out, _) = rig.explain_window("focused", "click settings");
    assert_eq!(out.matches("kept weak").count(), 10, "{out}");
    assert_eq!(
        out.matches("dropped: past the ten best weak matches").count(),
        2,
        "{out}"
    );
}

#[test]
fn a_sequence_gets_one_section_per_click_and_one_capture_each() {
    let rig = Rig::new();
    let (out, _) = rig.explain_window("focused", "click sign in and then click settings");
    assert_eq!(out.matches("\nwindow   ").count(), 2, "{out}");
    assert!(
        out.contains("outcome  click at 175,82") && out.contains("outcome  click at 230,132"),
        "{out}"
    );
    assert_eq!(rig.grim_calls(), 2, "{:?}", rig.calls());
    assert!(rig.untouched_by_a_click());
}

#[test]
fn the_json_is_one_parseable_document_with_the_click_traces() {
    let rig = Rig::new();
    let output = rig
        .command(&["explain", "--json", "--window", "focused", "click sign in"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(0));
    let document: serde_json::Value = serde_json::from_slice(&output.stdout).expect("stdout is one JSON document");
    assert_eq!(document["phrase"], "click sign in");
    assert!(document["steps"].is_array());
    let click = document["click"].as_array().expect("an array of traces");
    assert_eq!(click.len(), 1);
    let trace = &click[0];
    assert_eq!(trace["target"], "sign in");
    assert_eq!(trace["kind"], "run");
    assert_eq!(trace["info"]["mode"], "toplevel");
    assert_eq!(trace["info"]["image"], "256x154");
    assert_eq!(trace["used_pass"], "whole");
    assert_eq!(trace["outcome"], "click at 175,82");
    assert_eq!(trace["passes"][0]["verdicts"][0]["kept"], true);
    assert_eq!(rig.grim_calls(), 1);
    assert!(!rig.target_file().exists());
}

#[test]
fn the_json_without_window_has_no_click_and_a_phrase_that_never_clicked_has_an_empty_list() {
    let rig = Rig::new();
    let plain = rig.command(&["explain", "--json", "click sign in"]).output().unwrap();
    let document: serde_json::Value = serde_json::from_slice(&plain.stdout).unwrap();
    assert!(document["click"].is_null());
    let hints = rig
        .command(&["explain", "--json", "--window", "focused", "banana split"])
        .output()
        .unwrap();
    let document: serde_json::Value = serde_json::from_slice(&hints.stdout).unwrap();
    assert_eq!(document["click"], serde_json::json!([]));
}
