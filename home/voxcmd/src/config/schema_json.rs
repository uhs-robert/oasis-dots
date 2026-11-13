//! `integrations schema`: the JSON Schema of an integration TOML, for an editor's TOML language server
//!
//! Written by hand rather than derived: the serde types in `schema.rs` do not carry the rules `integrations check`
//! enforces. The property names come from the `*_KEYS` lists there, so a key added to a list reaches the schema, and
//! a test pins that the lists and the properties agree.
use super::schema::{ACTION_KEYS, FILE_KEYS, HELP_KEYS, SURFACE_KEYS, VERB_KEYS};
use serde_json::{Map, Value, json};

/// Draft 7 is the newest the TOML language servers (Taplo, Even Better TOML) all read.
const SCHEMA_DRAFT: &str = "http://json-schema.org/draft-07/schema#";

pub fn run() -> String {
    serde_json::to_string_pretty(&json_schema()).expect("a json value serializes")
}

pub fn json_schema() -> Value {
    let mut schema = table(FILE_KEYS, file_key, &["verbs"]);
    let root = schema.as_object_mut().expect("a table is an object");
    root.insert("$schema".to_string(), json!(SCHEMA_DRAFT));
    root.insert("title".to_string(), json!("voxcmd integration"));
    schema
}

/// An object schema over `keys`, closed with `additionalProperties: false`. Every caller is a table where
/// `integrations check` also rejects an unknown key, so the editor never flags a key that `check` accepts.
fn table(keys: &[&str], kind_of: fn(&str) -> Value, required: &[&str]) -> Value {
    let properties: Map<String, Value> = keys.iter().map(|key| (key.to_string(), kind_of(key))).collect();
    let mut object = json!({ "type": "object", "properties": properties, "additionalProperties": false });
    if !required.is_empty() {
        object["required"] = json!(required);
    }
    object
}

fn string(description: &str) -> Value {
    json!({ "type": "string", "description": description })
}

fn boolean(description: &str) -> Value {
    json!({ "type": "boolean", "description": description })
}

fn string_list(description: &str) -> Value {
    json!({ "type": "array", "items": { "type": "string" }, "description": description })
}

fn file_key(key: &str) -> Value {
    match key {
        "name" => string("Display name; the file stem when absent."),
        "fallback" => boolean("Tried only when no other integration offered an option."),
        "confirm" => boolean("Ask before running any verb."),
        "confirm_labels" => string_list("Action labels that ask before running."),
        "silent" => boolean("Run without a spoken or notified result."),
        "private_labels" => boolean("Keep candidate labels out of the logs."),
        "target_match" => json!({
            "enum": ["fuzzy", "words"],
            "default": "fuzzy",
            "description": "How a spoken target is matched to a candidate.",
        }),
        "match_ignore_words" => string_list("Words dropped before a target is matched."),
        "action_labels" => boolean("Whether the action names are offered as labels."),
        "force_prefixes" => string_list("Spoken prefixes that force this integration."),
        "define" => json!({
            "type": "object",
            "additionalProperties": { "type": "string" },
            "description": "Named patterns a verb's `match` can use.",
        }),
        "verbs" => json!({
            "type": "array",
            "items": table(VERB_KEYS, verb_key, &["action", "match"]),
            "description": "The phrases the integration takes, tried in order.",
        }),
        "help" => json!({
            "type": "array",
            "items": table(HELP_KEYS, help_key, &["action"]),
            "description": "What `help` lists for an action: a hook (`list`), one static row (`id`, `label`) or the candidates.",
        }),
        "examples" => string_list("Example phrases."),
        "actions" => json!({
            "type": "object",
            "additionalProperties": {
                "oneOf": [
                    string("A shell command to run."),
                    table(ACTION_KEYS, action_key, &[]),
                ],
            },
            "description": "The actions the verbs name.",
        }),
        "picker" => json!({
            "enum": ["hints"],
            "description": "How the integration's options are shown: `hints` numbers them over their boxes on screen.",
        }),
        "surface" => table(SURFACE_KEYS, surface_key, &["state_file"]),
        "mode" => mode(),
        _ => json!({}),
    }
}

fn verb_key(key: &str) -> Value {
    match key {
        "action" => string("The action to run."),
        "match" => string("The phrase pattern."),
        "label" => string("A name for the verb."),
        "requires" => string("An integration stem; the verb counts only while that integration is loaded."),
        _ => json!({}),
    }
}

fn help_key(key: &str) -> Value {
    match key {
        "action" => string("The action this entry describes."),
        "list" => string("A hook that prints the rows; excludes `id` and `label`."),
        "id" => string("The id of a static row; needs `label`."),
        "label" => string("The label of a static row."),
        _ => json!({}),
    }
}

fn surface_key(key: &str) -> Value {
    match key {
        "state_file" => string("File under the runtime dir whose `open` flag says the surface is open."),
        _ => json!({}),
    }
}

fn action_key(key: &str) -> Value {
    match key {
        "run" => string("The shell command."),
        "candidates" => string("A shell command that prints the candidates."),
        "provider" => string("A built-in candidate source."),
        "candidate_arg" => string("Reserved; nothing reads it yet."),
        "no_match" => string("What to say when no candidate matches."),
        "silent" => boolean("Run without a spoken or notified result."),
        "listen_for_pick" => boolean("Listen for the pick instead of asking on screen."),
        "free_text" => boolean("Take any words as the target."),
        "mode_switch" => boolean("The action switches the session's mode."),
        "mode_entry" => boolean("The action opens the integration's mode."),
        "enter_mode" => boolean("The action enters the mode."),
        "leave_mode" => string("The reason the action leaves the integration's mode with; needs a `[mode]` table."),
        "miss" => boolean("The action is the miss handler."),
        "wait" => string(
            "A built-in condition to wait for after the action: `active_window_is_id`, `active_window_changed`, `window_gone` or `popup_open:<name>`.",
        ),
        "wait_hook" => string("A hook to wait on after the action."),
        "timeout_secs" => json!({ "type": "number", "description": "Seconds before the action is given up." }),
        _ => json!({}),
    }
}

/// `deny_unknown_fields` on the serde types, so the loader itself rejects any other key here.
fn mode() -> Value {
    let seconds = || json!({ "type": "number" });
    json!({
        "type": "object",
        "additionalProperties": false,
        "properties": {
            "label": string("Name shown for the mode."),
            "exit_object": string("The word that follows `stop` or `off` to leave the mode."),
            "exit_phrases": string("Extra spoken phrases that leave the mode."),
            "exit_hint": string("Spoken hint on how to leave."),
            "bare_exits": boolean("Whether a bare `stop` leaves the mode."),
            "default_exits": boolean("Whether `<mode> stop` and `<mode> off` leave the mode."),
            "allows_switches": boolean("Whether other modes can be entered from this one."),
            "private": boolean("Keep the turns out of the logs."),
            "open_ended": boolean("Leaves the mode's time out of the session's."),
            "wake_listens": boolean("Kept in session.json; the wake listener no longer reads it."),
            "listen": {
                "type": "object",
                "additionalProperties": false,
                "properties": {
                    "silence_secs": seconds(),
                    "max_secs": seconds(),
                    "no_speech_secs": seconds(),
                },
            },
            "rewrite": {
                "type": "object",
                "additionalProperties": false,
                "properties": {
                    "drop": string("Pattern; a turn that matches routes nothing."),
                    "keep": string("Pattern; a turn that matches routes as spoken."),
                    "prefix": string("Words put before any other turn."),
                },
            },
            "rewrite_hook": string("A hook that rewrites the turn."),
            "ended": string("A command run when the mode ends."),
            "alive": string("A command that says whether the mode is still alive."),
            "timeout_secs": seconds(),
            "handle_turn": string("The action that handles each turn."),
            "endings": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["action", "match"],
                    "properties": {
                        "action": string("The action to run."),
                        "match": string("The pattern that ends the mode."),
                    },
                },
            },
            "one_recording": boolean("Keep one recording open across turns."),
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn property_names(value: &Value) -> Vec<String> {
        let mut names: Vec<String> = value["properties"].as_object().unwrap().keys().cloned().collect();
        names.sort();
        names
    }

    fn sorted(keys: &[&str]) -> Vec<String> {
        let mut names: Vec<String> = keys.iter().map(|key| key.to_string()).collect();
        names.sort();
        names
    }

    #[test]
    fn every_key_list_entry_is_a_property_with_a_description() {
        let schema = json_schema();
        assert_eq!(property_names(&schema), sorted(FILE_KEYS));
        let tables = [
            (&schema["properties"]["verbs"]["items"], VERB_KEYS),
            (&schema["properties"]["help"]["items"], HELP_KEYS),
            (&schema["properties"]["surface"], SURFACE_KEYS),
            (
                &schema["properties"]["actions"]["additionalProperties"]["oneOf"][1],
                ACTION_KEYS,
            ),
        ];
        for (table, keys) in tables {
            assert_eq!(property_names(table), sorted(keys));
            for (key, property) in table["properties"].as_object().unwrap() {
                assert!(
                    property.as_object().is_some_and(|p| !p.is_empty()),
                    "{key} has no schema"
                );
            }
        }
    }

    /// The keys serde accepts in a `deny_unknown_fields` table, read from its "expected ..." error (`a` or `b`, or one of
    /// `a`, `b`, ...).
    fn serde_keys(table_header: &str) -> Vec<String> {
        let text = format!("verbs = []\n{table_header}\nzz_unknown = 1\n");
        let error = super::super::schema::parse_toml(std::path::Path::new("m.toml"), &text).unwrap_err();
        let list = error
            .split(", expected ")
            .nth(1)
            .unwrap_or_else(|| panic!("no key list in: {error}"));
        let mut names: Vec<String> = list.split('`').skip(1).step_by(2).map(str::to_string).collect();
        names.sort();
        names
    }

    #[test]
    fn the_mode_tables_list_the_keys_serde_accepts() {
        let schema = json_schema();
        let mode = &schema["properties"]["mode"];
        assert_eq!(property_names(mode), serde_keys("[mode]"));
        assert_eq!(
            property_names(&mode["properties"]["listen"]),
            serde_keys("[mode.listen]")
        );
        assert_eq!(
            property_names(&mode["properties"]["rewrite"]),
            serde_keys("[mode.rewrite]")
        );
        assert_eq!(
            property_names(&mode["properties"]["endings"]["items"]),
            serde_keys("[[mode.endings]]")
        );
    }

    #[test]
    fn it_requires_verbs_and_is_closed_at_the_top() {
        let schema = json_schema();
        assert_eq!(schema["required"], json!(["verbs"]));
        assert_eq!(schema["additionalProperties"], json!(false));
        assert_eq!(schema["type"], "object");
    }
}
