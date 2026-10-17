//! lowercasing, punctuation strip, replacements.d, workspace ordinals (was normalize/apply_replacements)
use super::speech::{split_words, spoken_ordinal};
use std::path::Path;

/// Lowercase letters and digits only, one space between words: "Open Firefox, please!" is "open firefox please".
/// Apostrophes vanish ("what's" is "whats") and every other character becomes a space. A newline stays a newline,
/// and the trailing ones go, as the bash `$(...)` it replaces drops them.
pub fn normalize(text: &str) -> String {
    let mut squeezed = String::with_capacity(text.len());
    for character in text.to_lowercase().chars().filter(|&c| c != '\'') {
        let kept = if character.is_ascii_lowercase() || character.is_ascii_digit() || character == '\n' {
            character
        } else {
            ' '
        };
        if kept == ' ' && squeezed.ends_with(' ') {
            continue;
        }
        squeezed.push(kept);
    }
    let without_newlines = squeezed.trim_end_matches('\n');
    let without_leading = without_newlines.strip_prefix(' ').unwrap_or(without_newlines);
    without_leading.strip_suffix(' ').unwrap_or(without_leading).to_string()
}

/// The `spoken = canonical` lines of replacements.d, in file order (file names sorted bytewise).
#[derive(Debug, Default)]
pub struct Replacements {
    pairs: Vec<(String, String)>,
}

impl Replacements {
    /// Reads every regular, non-hidden file of `dir`. A missing directory holds none.
    pub fn load(dir: &Path) -> Self {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return Self::default();
        };
        let mut files: Vec<_> = entries
            .filter_map(Result::ok)
            .filter(|entry| !entry.file_name().to_string_lossy().starts_with('.'))
            .map(|entry| entry.path())
            .filter(|path| path.is_file())
            .collect();
        files.sort();
        let mut pairs = Vec::new();
        for file in files {
            let Ok(content) = std::fs::read_to_string(&file) else {
                continue;
            };
            for line in content.split('\n') {
                let line_start = line.trim_start_matches(char::is_whitespace);
                if line_start.is_empty() || line_start.starts_with('#') {
                    continue;
                }
                let Some((spoken, canonical)) = line.split_once('=') else {
                    continue;
                };
                let spoken = normalize(spoken);
                if !spoken.is_empty() {
                    pairs.push((spoken, normalize(canonical)));
                }
            }
        }
        Self { pairs }
    }
}

/// Applies replacements to normalized text, then names workspace ordinals. A replacement matches whole words only
/// (the spaces around it are part of the match, so two adjacent hits can share one space and the second is missed).
pub fn apply_replacements(text: &str, replacements: &Replacements) -> String {
    let mut padded = format!(" {text} ");
    for (spoken, canonical) in &replacements.pairs {
        padded = padded.replace(&format!(" {spoken} "), &format!(" {canonical} "));
    }
    let trimmed = padded.strip_prefix(' ').unwrap_or(&padded);
    name_workspace_ordinals(trimmed.strip_suffix(' ').unwrap_or(trimmed))
}

/// The text with "the second workspace" or "twenty first desktop" rewritten to "workspace 2" / "workspace 21", so the
/// integrations and the keybinds' "Go to Workspace 2" see one form. Only an ordinal next to the noun counts;
/// "workspace 2", and a count such as "two workspaces", are left alone.
pub fn name_workspace_ordinals(text: &str) -> String {
    let mut out: Vec<String> = Vec::new();
    for word in split_words(text) {
        if word == "workspace" || word == "desktop" {
            let mut position = None;
            if out.len() >= 2
                && let Some(found) = spoken_ordinal(&format!("{} {}", out[out.len() - 2], out[out.len() - 1]))
            {
                position = Some(found);
                out.truncate(out.len() - 2);
            } else if let Some(found) = out.last().and_then(|previous| spoken_ordinal(previous)) {
                position = Some(found);
                out.pop();
            }
            if let Some(position) = position {
                if out.last().is_some_and(|previous| previous == "the") {
                    out.pop();
                }
                out.push("workspace".to_string());
                out.push(position.to_string());
                continue;
            }
        }
        out.push(word.to_string());
    }
    out.join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_keeps_letters_and_digits() {
        assert_eq!(normalize("Open Firefox, please!"), "open firefox please");
        assert_eq!(normalize("What's  the   time?"), "whats the time");
        assert_eq!(normalize("3:30 p.m."), "3 30 p m");
        assert_eq!(normalize("  "), "");
    }

    #[test]
    fn workspace_ordinals_become_numbers() {
        assert_eq!(
            name_workspace_ordinals("go to the second workspace"),
            "go to workspace 2"
        );
        assert_eq!(name_workspace_ordinals("twenty first desktop"), "workspace 21");
        assert_eq!(name_workspace_ordinals("two workspaces"), "two workspaces");
        assert_eq!(name_workspace_ordinals("workspace 2"), "workspace 2");
    }

    #[test]
    fn replacements_apply_to_whole_words() {
        let replacements = Replacements {
            pairs: vec![("pre size".into(), "resize".into())],
        };
        assert_eq!(apply_replacements("pre size to 1200", &replacements), "resize to 1200");
        assert_eq!(apply_replacements("compre size", &replacements), "compre size");
    }
}
