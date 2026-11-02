//! helpers shared by the integration test crates

#[allow(dead_code)]
/// Dead, or a zombie nobody has reaped yet.
pub fn gone_within(pid: i32, wait: std::time::Duration) -> bool {
    let deadline = std::time::Instant::now() + wait;
    loop {
        let state = std::fs::read_to_string(format!("/proc/{pid}/stat"))
            .ok()
            .and_then(|stat| stat.rsplit_once(')')?.1.trim_start().chars().next());
        if matches!(state, None | Some('Z')) {
            return true;
        }
        if std::time::Instant::now() >= deadline {
            return false;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
}

/// A live process whose command line is `voxcmd ask <kind>`, which is how a pending pick's asker is known. A bash
/// script named `ask` runs with argv[0] `voxcmd` (`exec -a`), and loops rather than exec-ing sleep, which would rename
/// the process. Returns once /proc shows that command line: until then it is still the starting bash's.
#[allow(dead_code)]
pub fn spawn_fake_asker(dir: &std::path::Path, kind: &str) -> std::process::Child {
    static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let script_dir = dir.join(format!(
        "fake-asker-{}",
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&script_dir).unwrap();
    std::fs::write(script_dir.join("ask"), "while :; do sleep 0.5; done\n").unwrap();
    let asker = std::process::Command::new("bash")
        .current_dir(&script_dir)
        .args(["-c", &format!("exec -a voxcmd bash ask {kind}")])
        .spawn()
        .unwrap();
    let wanted = format!("voxcmd\0ask\0{kind}\0").into_bytes();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    while std::fs::read(format!("/proc/{}/cmdline", asker.id())).ok().as_deref() != Some(wanted.as_slice()) {
        assert!(
            std::time::Instant::now() < deadline,
            "the fake asker never became `voxcmd ask {kind}`"
        );
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    asker
}
