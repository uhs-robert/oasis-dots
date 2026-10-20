//! the no-match log: one `<date>\t<phrase>` line per phrase nothing matched, kept to the last 1000 (was `log_no_match`)
//!
//! The bash voxcmd appends to the same file under the same lock, so either binary may write while both are installed.
//! `log misses` reads it back; `log errors` reads the bar's notification history instead.
use crate::exit::CliError;
use crate::{paths, process, text};
use std::fs::OpenOptions;
use std::io::Write;
use std::os::fd::AsRawFd;
use std::path::Path;
use std::process::Command;

/// Lines kept; the file is cut back to this once it holds a tenth more.
const KEEP_LINES: usize = 1000;

/// Records a phrase that matched nothing. `private`: it was forced to an integration whose labels are screen text,
/// which would then be in the phrase.
pub fn log_no_match(phrase: &str, private: bool) {
    if phrase.is_empty() || private {
        return;
    }
    let date = jiff::Zoned::now().strftime("%Y-%m-%dT%H:%M:%S%:z").to_string();
    // A log that cannot be written is not worth failing the command for.
    let _ = append(&paths::no_match_log(), &date, phrase, KEEP_LINES);
}

fn append(log: &Path, date: &str, phrase: &str, keep: usize) -> std::io::Result<()> {
    if let Some(dir) = log.parent() {
        std::fs::create_dir_all(dir)?;
    }
    // The lock keeps another voxcmd's append from landing in the file a trim is about to replace.
    let lock = OpenOptions::new()
        .create(true)
        .append(true)
        .open(format!("{}.lock", log.display()))?;
    // SAFETY: flock on a descriptor this function owns; the lock is released when `lock` closes.
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    let mut file = OpenOptions::new().create(true).append(true).open(log)?;
    writeln!(file, "{date}\t{phrase}")?;
    let text = std::fs::read_to_string(log)?;
    let lines: Vec<&str> = text.lines().collect();
    if lines.len() > keep + keep / 10 {
        let temp = log.with_extension("log.tmp");
        std::fs::write(&temp, format!("{}\n", lines[lines.len() - keep..].join("\n")))?;
        std::fs::rename(&temp, log)?;
    }
    Ok(())
}

/// `log misses [N] [--json]`: the last `count` lines of the log, as written, or `{time, phrase}` objects.
pub fn misses(count: u32, json: bool) -> Result<Option<String>, CliError> {
    // A log that is not there yet has no misses.
    let text = std::fs::read(paths::no_match_log())
        .map_or_else(|_| String::new(), |bytes| String::from_utf8_lossy(&bytes).into_owned());
    let lines: Vec<&str> = text.lines().collect();
    let last = &lines[lines.len().saturating_sub(count as usize)..];
    if json {
        let records: Vec<serde_json::Value> = last
            .iter()
            .map(|line| {
                let (time, phrase) = line.split_once('\t').unwrap_or(("", line));
                serde_json::json!({ "time": time, "phrase": phrase })
            })
            .collect();
        return Ok(Some(serde_json::Value::Array(records).to_string()));
    }
    // Printed here rather than returned: no lines must print nothing, not an empty line.
    let mut out = std::io::stdout().lock();
    for line in last {
        // A closed pipe (`| head`) is the reader's choice, not a failure.
        let _ = writeln!(out, "{line}");
    }
    Ok(None)
}

/// `log errors [N] [--json]`: the bar's last `count` kept notifications from voxcmd, which are its errors as info toasts
/// are transient. One line each: `<date> <time>  <summary>: <body>`, the time in the bar's clock format.
pub fn errors(count: u32, json: bool) -> Result<Option<String>, CliError> {
    let mut command = Command::new(paths::qs_ipc());
    command.args(["call", "notifications", "history", &count.to_string(), "voxcmd"]);
    // run_to_end captures stderr, so the bar's own complaints never reach the terminal; the one line below replaces them.
    let history = process::run_to_end(&mut command)
        .ok()
        .filter(|outcome| outcome.code() == Some(0))
        .and_then(|outcome| serde_json::from_str::<serde_json::Value>(&outcome.stdout).ok())
        .and_then(|value| match value {
            serde_json::Value::Array(entries) => Some(entries),
            _ => None,
        })
        .ok_or_else(|| CliError::failed("log errors", "bar not running"))?;
    let field = |entry: &serde_json::Value, name: &str| {
        entry
            .get(name)
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    if json {
        let errors: Vec<serde_json::Value> = history
            .iter()
            .map(|entry| {
                serde_json::json!({
                    "time": field(entry, "time"),
                    "summary": field(entry, "summary"),
                    "body": field(entry, "body"),
                })
            })
            .collect();
        return Ok(Some(serde_json::Value::Array(errors).to_string()));
    }
    let format = if text::speech::clock_is_twelve_hour() {
        "%F %-I:%M%P"
    } else {
        "%F %H:%M"
    };
    let lines: Vec<String> = history
        .iter()
        .map(|entry| {
            let time = field(entry, "time").parse::<jiff::Timestamp>().map_or_else(
                |_| field(entry, "time").to_string(),
                |stamp| {
                    stamp
                        .to_zoned(jiff::tz::TimeZone::system())
                        .strftime(format)
                        .to_string()
                },
            );
            format!(
                "{time}  {}: {}",
                field(entry, "summary"),
                field(entry, "body").replace('\n', " ")
            )
        })
        .collect();
    Ok((!lines.is_empty()).then(|| lines.join("\n")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_phrase_is_a_dated_line() {
        let dir = tempfile::tempdir().unwrap();
        let log = dir.path().join("state/no-match.log");
        append(&log, "2026-10-17T12:00:00+00:00", "make me a sandwich", 1000).unwrap();
        assert_eq!(
            std::fs::read_to_string(&log).unwrap(),
            "2026-10-17T12:00:00+00:00\tmake me a sandwich\n"
        );
    }

    #[test]
    fn the_log_is_cut_back_to_the_last_lines_once_a_tenth_over() {
        let dir = tempfile::tempdir().unwrap();
        let log = dir.path().join("no-match.log");
        for number in 0..=11 {
            append(&log, "d", &format!("phrase {number}"), 10).unwrap();
        }
        // The 12th line is the first past 10 + 1: it trims to the newest 10.
        let text = std::fs::read_to_string(&log).unwrap();
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines.len(), 10);
        assert_eq!(lines[0], "d\tphrase 2");
        assert_eq!(lines[9], "d\tphrase 11");
    }

    #[test]
    fn concurrent_writers_lose_no_line() {
        let dir = tempfile::tempdir().unwrap();
        let log = dir.path().join("no-match.log");
        std::thread::scope(|scope| {
            for writer in 0..8 {
                let log = &log;
                scope.spawn(move || {
                    for number in 0..10 {
                        append(log, "d", &format!("{writer}-{number}"), 1000).unwrap();
                    }
                });
            }
        });
        assert_eq!(std::fs::read_to_string(&log).unwrap().lines().count(), 80);
    }
}
