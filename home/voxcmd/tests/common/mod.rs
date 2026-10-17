//! helpers shared by the integration test crates

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
