//! The keybind list cache of keybinds.sh and its hook-cache.sh helper, driven through bash with fake XDG dirs and a fake
//! `hyprctl`. XDG_CACHE_HOME always points into the sandbox, so the real cache is never read or written.
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const INTEGRATIONS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/.config/voxcmd/integrations");
const SHARE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/.local/share/voxcmd");

struct Sandbox {
    root: tempfile::TempDir,
}

impl Sandbox {
    fn new() -> Self {
        let sandbox = Self {
            root: tempfile::tempdir().unwrap(),
        };
        for dir in ["home", "bin"] {
            fs::create_dir_all(sandbox.path(dir)).unwrap();
        }
        // The stub counts its calls and prints $STUB_BINDS_FILE, or fails when STUB_FAIL is set.
        let stub = sandbox.path("bin/hyprctl");
        fs::write(
            &stub,
            "#!/bin/sh\necho x >>\"$STUB_COUNT_FILE\"\n[ -z \"$STUB_FAIL\" ] || exit 1\ncat \"$STUB_BINDS_FILE\"\n",
        )
        .unwrap();
        fs::set_permissions(&stub, fs::Permissions::from_mode(0o755)).unwrap();
        sandbox.set_binds(&[("Open Terminal", "1")]);
        sandbox
    }

    fn path(&self, relative: &str) -> PathBuf {
        self.root.path().join(relative)
    }

    fn cache_dir(&self) -> PathBuf {
        self.path("cache/voxcmd")
    }

    fn set_mtime(&self, file: &Path, seconds: u64) {
        let status = Command::new("touch")
            .arg("-d")
            .arg(format!("@{seconds}"))
            .arg(file)
            .status()
            .unwrap();
        assert!(status.success());
    }

    fn set_binds(&self, binds: &[(&str, &str)]) {
        fs::write(self.path("binds.json"), binds_json(binds)).unwrap();
    }

    /// A bash running the script with the sandbox's environment and nothing else; `env` overrides or adds.
    fn bash(&self, script: &str, env: &[(&str, &str)]) -> Command {
        let mut command = Command::new("bash");
        command
            .args(["--noprofile", "--norc", "-c", script])
            .env_clear()
            .env("PATH", format!("{}:/usr/bin:/bin", self.path("bin").display()))
            .env("HOME", self.path("home"))
            .env("XDG_CACHE_HOME", self.path("cache"))
            .env("VOXCMD_SHARE_DIR", SHARE)
            .env("VOXCMD_INTEGRATION_DIR", INTEGRATIONS)
            .env("STUB_BINDS_FILE", self.path("binds.json"))
            .env("STUB_COUNT_FILE", self.path("hyprctl-calls"))
            .envs(env.iter().copied());
        command
    }

    /// Runs bash over the library.
    fn run(&self, library: &str, body: &str, env: &[(&str, &str)]) -> String {
        let script = format!(". \"{library}\"\n{body}");
        let output = self.bash(&script, env).output().unwrap();
        assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
        assert!(output.stderr.is_empty(), "{}", String::from_utf8_lossy(&output.stderr));
        String::from_utf8(output.stdout).unwrap()
    }

    fn binds(&self, env: &[(&str, &str)]) -> String {
        self.run(&format!("{INTEGRATIONS}/keybinds.sh"), "bind_lists", env)
    }

    fn hyprctl_calls(&self) -> usize {
        fs::read_to_string(self.path("hyprctl-calls")).map_or(0, |text| text.lines().count())
    }
}

fn binds_json(binds: &[(&str, &str)]) -> String {
    let items: Vec<String> = binds
        .iter()
        .map(|(description, arg)| {
            format!(
                r#"{{"has_description":true,"description":"{description}","dispatcher":"__lua","arg":"{arg}","mouse":false,"key":"a","submap":""}}"#
            )
        })
        .collect();
    format!("[{}]", items.join(","))
}

#[test]
fn an_unwritable_cache_dir_still_gives_the_right_list() {
    let sandbox = Sandbox::new();
    let uncached = sandbox.binds(&[]);
    fs::remove_dir_all(sandbox.path("cache")).unwrap();
    // A file where the cache dir belongs, and a read-only dir: neither can be written.
    fs::write(sandbox.path("cache"), "a file").unwrap();
    assert_eq!(sandbox.binds(&[]), uncached);
    fs::remove_file(sandbox.path("cache")).unwrap();
    fs::create_dir_all(sandbox.cache_dir()).unwrap();
    fs::set_permissions(sandbox.cache_dir(), fs::Permissions::from_mode(0o500)).unwrap();
    assert_eq!(sandbox.binds(&[]), uncached);
    assert_eq!(fs::read_dir(sandbox.cache_dir()).unwrap().count(), 0);
    fs::set_permissions(sandbox.cache_dir(), fs::Permissions::from_mode(0o700)).unwrap();
}

#[test]
fn keybinds_cold_run_builds_and_a_warm_run_matches() {
    let sandbox = Sandbox::new();
    let cold = sandbox.binds(&[]);
    assert!(cold.contains("Open Terminal"), "{cold}");
    assert!(sandbox.cache_dir().join("keybinds.json").is_file());
    assert_eq!(sandbox.binds(&[]), cold);
    assert_eq!(
        sandbox.hyprctl_calls(),
        2,
        "hyprctl is still asked every time, it is the key"
    );
}

#[test]
fn different_hyprctl_output_gives_new_lists() {
    let sandbox = Sandbox::new();
    sandbox.binds(&[]);
    sandbox.set_binds(&[("Open Terminal", "1"), ("Open Browser", "2")]);
    let list = sandbox.binds(&[]);
    assert!(list.contains("Open Browser"), "{list}");
    sandbox.set_binds(&[("Open Terminal", "7")]);
    let list = sandbox.binds(&[]);
    assert!(list.contains(r#""id":"7""#) && !list.contains("Open Browser"), "{list}");
}

#[test]
fn editing_the_exclusion_list_invalidates() {
    let sandbox = Sandbox::new();
    let copy = sandbox.path("copy");
    fs::create_dir_all(&copy).unwrap();
    let library = copy.join("keybinds.sh");
    let original = fs::read_to_string(format!("{INTEGRATIONS}/keybinds.sh")).unwrap();
    fs::write(&library, &original).unwrap();
    let library = library.to_str().unwrap();
    assert!(sandbox.run(library, "bind_lists", &[]).contains("Open Terminal"));
    fs::write(library, original.replace("\"voxtype\"", "\"voxtype\"\n  \"terminal\"")).unwrap();
    let list = sandbox.run(library, "bind_lists", &[]);
    assert!(!list.contains("Open Terminal"), "{list}");
}

#[test]
fn a_same_size_edit_of_the_exclusion_list_with_the_mtime_put_back_invalidates() {
    let sandbox = Sandbox::new();
    let copy = sandbox.path("copy");
    fs::create_dir_all(&copy).unwrap();
    let library = copy.join("keybinds.sh");
    let original = fs::read_to_string(format!("{INTEGRATIONS}/keybinds.sh")).unwrap();
    fs::write(&library, &original).unwrap();
    sandbox.set_mtime(&library, 1_000_000);
    let library_path = library.to_str().unwrap();
    assert!(sandbox.run(library_path, "bind_lists", &[]).contains("Open Terminal"));
    // "password" and "terminal" are the same length.
    fs::write(&library, original.replace("\"password\"", "\"terminal\"")).unwrap();
    sandbox.set_mtime(&library, 1_000_000);
    let list = sandbox.run(library_path, "bind_lists", &[]);
    assert!(!list.contains("Open Terminal"), "{list}");
}

#[test]
fn a_failed_hyprctl_is_never_cached() {
    let sandbox = Sandbox::new();
    let failed = sandbox.binds(&[("STUB_FAIL", "1")]);
    assert_eq!(failed.trim(), r#"{"binds":[],"submaps":[],"mode_binds":[]}"#);
    assert!(!sandbox.cache_dir().join("keybinds.json").exists());
    let after = sandbox.binds(&[]);
    assert!(after.contains("Open Terminal"), "{after}");
}

#[test]
fn a_cached_list_is_not_served_to_a_failing_hyprctl() {
    let sandbox = Sandbox::new();
    sandbox.binds(&[]);
    let failed = sandbox.binds(&[("STUB_FAIL", "1")]);
    assert!(!failed.contains("Open Terminal"), "{failed}");
}

#[test]
fn a_reader_never_sees_half_a_cache_file_while_writers_replace_it() {
    let sandbox = Sandbox::new();
    // Big enough that a non-atomic write would take several write calls.
    let many: Vec<(String, String)> = (0..4000).map(|n| (format!("Bind number {n}"), n.to_string())).collect();
    let refs: Vec<(&str, &str)> = many.iter().map(|(d, a)| (d.as_str(), a.as_str())).collect();
    fs::write(sandbox.path("binds-a.json"), binds_json(&refs)).unwrap();
    fs::write(sandbox.path("binds-b.json"), binds_json(&refs[..3999])).unwrap();
    let library = format!("{INTEGRATIONS}/keybinds.sh");
    let expected_a = sandbox.run(
        &library,
        "bind_lists",
        &[("STUB_BINDS_FILE", sandbox.path("binds-a.json").to_str().unwrap())],
    );
    let expected_b = sandbox.run(
        &library,
        "bind_lists",
        &[("STUB_BINDS_FILE", sandbox.path("binds-b.json").to_str().unwrap())],
    );
    assert_ne!(expected_a, expected_b);

    // Start empty, so every file the reader sees was written by a writer below and not left by the runs above.
    fs::remove_dir_all(sandbox.cache_dir()).unwrap();
    // The two writers use different binds files, so each one keeps replacing the other's complete file.
    let writers: Vec<_> = ["a", "b"]
        .iter()
        .map(|which| {
            let script = format!(". \"{library}\"; for _ in $(seq 40); do bind_lists >/dev/null || exit 1; done");
            let binds = sandbox.path(&format!("binds-{which}.json"));
            sandbox
                .bash(&script, &[("STUB_BINDS_FILE", binds.to_str().unwrap())])
                .stderr(std::process::Stdio::piped())
                .spawn()
                .unwrap()
        })
        .collect();

    let file = sandbox.cache_dir().join("keybinds.json");
    let mut seen = 0;
    let mut writers = writers;
    loop {
        if let Ok(bytes) = fs::read(&file) {
            let text = String::from_utf8(bytes).expect("a whole file is text");
            let lines: Vec<&str> = text.lines().collect();
            assert_eq!(lines.len(), 3, "key, payload, end marker; got {} lines", lines.len());
            assert_eq!(lines[2], "#end");
            assert!(
                lines[1] == expected_a.trim() || lines[1] == expected_b.trim(),
                "a payload that is neither list"
            );
            seen += 1;
        }
        let mut running = false;
        for writer in &mut writers {
            running |= writer.try_wait().unwrap().is_none();
        }
        if !running {
            break;
        }
    }
    for writer in writers {
        let output = writer.wait_with_output().unwrap();
        assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
        assert!(output.stderr.is_empty(), "{}", String::from_utf8_lossy(&output.stderr));
    }
    assert!(seen > 0, "the reader never saw the file");
    let leftovers: Vec<_> = fs::read_dir(sandbox.cache_dir())
        .unwrap()
        .map(|entry| entry.unwrap().file_name().into_string().unwrap())
        .filter(|name| name.ends_with(".tmp"))
        .collect();
    assert!(leftovers.is_empty(), "{leftovers:?}");
}

#[test]
fn editing_the_shared_cache_library_invalidates() {
    let sandbox = Sandbox::new();
    let share = sandbox.path("share");
    fs::create_dir_all(&share).unwrap();
    for entry in fs::read_dir(SHARE).unwrap() {
        let entry = entry.unwrap();
        if entry.file_name().to_string_lossy().ends_with(".sh") {
            fs::copy(entry.path(), share.join(entry.file_name())).unwrap();
        }
    }
    let share = share.to_str().unwrap();
    let keybinds = format!("{INTEGRATIONS}/keybinds.sh");
    let env = [("VOXCMD_SHARE_DIR", share)];
    sandbox.run(&keybinds, "bind_lists", &env);
    let key_line = || {
        fs::read_to_string(sandbox.cache_dir().join("keybinds.json"))
            .unwrap()
            .lines()
            .next()
            .unwrap()
            .to_string()
    };
    let before = key_line();
    let library = format!("{share}/hook-cache.sh");
    fs::write(
        &library,
        format!("{}\n# edited\n", fs::read_to_string(&library).unwrap()),
    )
    .unwrap();
    sandbox.run(&keybinds, "bind_lists", &env);
    assert_ne!(key_line(), before);
}

#[test]
fn a_stale_temp_file_from_a_killed_writer_is_swept_on_the_next_write() {
    let sandbox = Sandbox::new();
    sandbox.binds(&[]);
    let stale = sandbox.cache_dir().join(".keybinds.json.99999.tmp");
    fs::write(&stale, "half").unwrap();
    sandbox.set_mtime(&stale, 1_000);
    sandbox.set_binds(&[("Open Browser", "2")]);
    sandbox.binds(&[]);
    assert!(!stale.exists());
}

#[test]
fn a_corrupt_or_cut_short_cache_is_rebuilt() {
    let sandbox = Sandbox::new();
    let cold = sandbox.binds(&[]);
    let file = sandbox.cache_dir().join("keybinds.json");
    let good = fs::read_to_string(&file).unwrap();
    let lines: Vec<&str> = good.lines().collect();
    let damaged = [
        "garbage\0\u{1}not a cache".to_string(),
        // Cut short: no end marker.
        good[..good.len() - 5].to_string(),
        // Another key on the first line.
        format!("not-the-key\n{}\n#end\n", lines[1]),
        String::new(),
    ];
    for (round, text) in damaged.iter().enumerate() {
        fs::write(&file, text).unwrap();
        let calls_before = sandbox.hyprctl_calls();
        let list = sandbox.binds(&[]);
        assert_eq!(list, cold, "round {round}");
        assert_eq!(
            fs::read_to_string(&file).unwrap(),
            good,
            "round {round}: rebuilt in place"
        );
        assert_eq!(sandbox.hyprctl_calls(), calls_before + 1);
    }
}

#[test]
fn a_failing_jq_is_never_cached() {
    let sandbox = Sandbox::new();
    let jq = sandbox.path("bin/jq");
    fs::write(&jq, "#!/bin/sh\nexit 1\n").unwrap();
    fs::set_permissions(&jq, fs::Permissions::from_mode(0o755)).unwrap();
    let failed = sandbox.binds(&[]);
    assert_eq!(failed.trim(), "{}");
    assert!(!sandbox.cache_dir().join("keybinds.json").exists());
    fs::remove_file(&jq).unwrap();
    assert!(sandbox.binds(&[]).contains("Open Terminal"));
}
