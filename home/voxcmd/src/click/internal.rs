//! The hidden entry points the suites reach the click code through; deleted with the bash matcher (3.2).
use super::matcher::{Matcher, Options};
use crate::cli::ClickMatchArgs;
use crate::exit::CliError;
use std::io::{Read, Write};

/// `voxcmd internal click-match`: the awk matcher's stdin and stdout. The target is in `CLICK_TARGET` (not argv, so a
/// backslash in it survives), the trace on stderr.
pub fn click_match(args: &ClickMatchArgs) -> Result<Option<String>, CliError> {
    let target = std::env::var_os("CLICK_TARGET").unwrap_or_default();
    let mut input = Vec::new();
    std::io::stdin()
        .read_to_end(&mut input)
        .map_err(|error| CliError::failed("click-match", format!("reading stdin: {error}")))?;
    let input = String::from_utf8_lossy(&input);
    let mut matcher = Matcher::new(&target.to_string_lossy(), Options::new(args.spans, args.explain));
    let mut lines: Vec<&str> = input.split('\n').collect();
    if lines.last() == Some(&"") {
        lines.pop();
    }
    for line in lines {
        matcher.feed(line);
    }
    let output = matcher.finish();
    let mut stderr = std::io::stderr().lock();
    for event in &output.trace {
        let _ = writeln!(stderr, "{}", event.tsv());
    }
    if let Some(error) = output.error {
        return Err(CliError::usage("click-match", error.to_string()));
    }
    let mut stdout = std::io::stdout().lock();
    for candidate in &output.candidates {
        let _ = writeln!(stdout, "{}", candidate.tsv());
    }
    Ok(None)
}
