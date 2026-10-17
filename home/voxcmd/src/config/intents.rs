//! built-in intents plus intents.local; `util intents`
//!
//! An intent is the spoken forms of a verb that several integrations share, written `{open}`, `{focus}`, ... in a
//! verb pattern. The verb only narrows what is meant and the noun after it decides, so one form may serve several
//! intents ("start" opens an app, activates caffeine and starts a recording).
use crate::exit::CliError;
use crate::text::normalize::normalize;
use std::collections::BTreeMap;
use std::path::Path;

const BUILT_IN: [(&str, &str); 9] = [
    ("open", "open|launch|start|bring up|pull up"),
    ("show", "show|display|open|bring up|pull up"),
    ("focus", "focus|go to|switch to|jump to|take me to"),
    ("activate", "activate|enter|turn on|switch on|enable|engage|start"),
    (
        "deactivate",
        "deactivate|exit|leave|turn off|switch off|disable|disengage|end",
    ),
    ("close", "close|quit|kill"),
    ("set", "set|change|make|adjust"),
    ("start", "start|begin|kick off"),
    ("stop", "stop|end|finish"),
];

/// Intent name to its forms, in order. Forms are normalized words, so they hold no regex syntax.
#[derive(Debug, Clone)]
pub struct Intents {
    forms: BTreeMap<String, Vec<String>>,
}

impl Default for Intents {
    fn default() -> Self {
        let forms = BUILT_IN
            .iter()
            .map(|(name, forms)| (name.to_string(), forms.split('|').map(str::to_string).collect()))
            .collect();
        Self { forms }
    }
}

impl Intents {
    /// The built-in intents plus `intents.local` in `config_dir`, whose `intent = form, form` lines append forms; a
    /// name that is no intent yet declares one.
    pub fn load(config_dir: &Path) -> Self {
        let mut intents = Self::default();
        if let Ok(content) = std::fs::read_to_string(config_dir.join("intents.local")) {
            intents.add_local(&content);
        }
        intents
    }

    fn add_local(&mut self, content: &str) {
        for line in content.lines() {
            let line_start = line.trim_start();
            if line_start.is_empty() || line_start.starts_with('#') {
                continue;
            }
            let Some((name, forms)) = line.split_once('=') else {
                continue;
            };
            let name = normalize(name);
            // Placeholders, not intents: an intent of that name would replace the placeholder.
            let is_word = !name.is_empty() && name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit());
            if !is_word || name == "target" || name == "number" {
                continue;
            }
            let forms: Vec<String> = forms
                .split(',')
                .map(normalize)
                .filter(|form| !form.is_empty())
                .collect();
            // A name with no forms stays undeclared, so `{name}` in a pattern is left as written, as in bash.
            if !forms.is_empty() {
                self.forms.entry(name).or_default().extend(forms);
            }
        }
    }

    pub fn forms(&self, name: &str) -> Option<&[String]> {
        self.forms.get(name).map(Vec::as_slice)
    }
}

/// `voxcmd util intents <name>`: the forms, one per line.
pub fn run(name: &str) -> Result<String, CliError> {
    let intents = Intents::load(&crate::paths::config_dir());
    match intents.forms(name) {
        Some(forms) => Ok(forms.join("\n")),
        None => Err(CliError::failed("util intents", format!("no intent named {name:?}"))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_lines_append_forms_and_declare_new_intents() {
        let mut intents = Intents::default();
        intents.add_local("# comment\nopen = Fire Up, spin-up\nzap = zap,, blast\ntarget = no\n  \nbad line\n");
        assert_eq!(
            intents.forms("open").unwrap(),
            ["open", "launch", "start", "bring up", "pull up", "fire up", "spin up"]
        );
        assert_eq!(intents.forms("zap").unwrap(), ["zap", "blast"]);
        assert!(intents.forms("target").is_none());
    }
}
