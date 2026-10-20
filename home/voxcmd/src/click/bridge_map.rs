//! Recognises the shipped `click.sh` in the bash voxcmd's dump and gives its click actions to the built-ins, so a
//! click no longer starts bash for its lookup, its click or its numbered boxes. Goes with the bridge in 3.2.
//!
//! The dump shows commands and hook names, not function bodies, so "the shipped file" is decided by those: the stem,
//! the hooks it defines and the exact command of each action the built-ins replace. A file that changes one of
//! them is the user's own and stays on the bridge. One that keeps all of them and rewrites only a function body
//! (`candidates`, `click_at`) is served by the built-ins too; the dump cannot tell, and a hash would break at every
//! edit of the shipped file.
use crate::config::schema::{Builtin, Candidates, Integration, Picker, Provider};
use std::collections::BTreeMap;

/// The actions that click, each running `click_at "$id"`.
const CLICKS: [&str; 4] = ["click", "right_click", "double_click", "triple_click"];

/// What the shipped file defines as the dump reports it: the commands of the actions that become built-ins.
const FINGERPRINT: [(&str, &str); 6] = [
    ("click", "click_at \"$id\""),
    ("right_click", "click_at \"$id\""),
    ("double_click", "click_at \"$id\""),
    ("triple_click", "click_at \"$id\""),
    ("no_text", "no_text"),
    ("show_hints", "show_hints"),
];

/// Whether the dump of file `stem` is the shipped click.sh's.
fn is_shipped(stem: &str, commands: &BTreeMap<String, String>, hooks: &[String]) -> bool {
    stem == "click"
        && ["candidates", "pick_box"]
            .iter()
            .all(|hook| hooks.iter().any(|defined| defined == hook))
        && FINGERPRINT
            .iter()
            .all(|(action, command)| commands.get(*action).map(String::as_str) == Some(*command))
}

/// Moves the click actions of a loaded bash integration onto the built-ins when it is the shipped click.sh. Mode
/// actions (`session_begin click ...`) and everything else stay on the bridge.
pub fn adapt(integration: &mut Integration, commands: &BTreeMap<String, String>, hooks: &[String]) {
    if !is_shipped(&integration.stem, commands, hooks) {
        return;
    }
    for action in CLICKS {
        if let Some(declared) = integration.actions.get_mut(action) {
            declared.candidates = Some(Candidates::Builtin(Provider::ScreenText));
            declared.builtin = Some(Builtin::ClickAt(None));
        }
    }
    for (action, builtin) in [("no_text", Builtin::NoText), ("show_hints", Builtin::ShowHints)] {
        if let Some(declared) = integration.actions.get_mut(action) {
            declared.builtin = Some(builtin);
        }
    }
    integration.picker = Some(Picker::Hints);
}

#[cfg(test)]
mod tests {
    use crate::config::legacy::parse_dump;
    use crate::config::schema::{Builtin, Candidates, Integration, Picker, Provider};

    fn dump() -> String {
        std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/legacy-dump.jsonl"))
            .expect("run gen-match-goldens.sh")
    }

    fn click_of(dump: &str) -> Integration {
        parse_dump(dump)
            .unwrap()
            .into_iter()
            .find(|integration| integration.stem == "click")
            .expect("the fixture dumps click.sh")
    }

    /// The fixture's click line, edited as JSON text.
    fn edited(from: &str, to: &str) -> String {
        let dump = dump();
        assert!(dump.contains(from), "the fixture no longer holds {from}");
        dump.replacen(from, to, 1)
    }

    fn is_bridged(integration: &Integration) -> bool {
        integration.actions.values().all(|action| action.builtin.is_none())
            && integration.picker.is_none()
            && !integration
                .actions
                .values()
                .any(|action| matches!(action.candidates, Some(Candidates::Builtin(_))))
    }

    #[test]
    fn the_shipped_click_sh_gets_the_built_ins_for_its_click_actions_and_its_picker() {
        let click = click_of(&dump());
        for action in ["click", "right_click", "double_click", "triple_click"] {
            let declared = &click.actions[action];
            assert!(
                matches!(declared.candidates, Some(Candidates::Builtin(Provider::ScreenText))),
                "{action}"
            );
            assert_eq!(declared.builtin, Some(Builtin::ClickAt(None)), "{action}");
            // The command text stays what explain prints.
            assert_eq!(declared.run, "click_at \"$id\"");
        }
        assert_eq!(click.actions["no_text"].builtin, Some(Builtin::NoText));
        assert_eq!(click.actions["show_hints"].builtin, Some(Builtin::ShowHints));
        assert_eq!(click.picker, Some(Picker::Hints));
    }

    #[test]
    fn the_mode_actions_and_other_files_stay_on_the_bridge() {
        let click = click_of(&dump());
        for action in ["click_mode", "stop_clicking"] {
            assert!(click.actions[action].builtin.is_none(), "{action}");
            assert!(matches!(
                click.actions[action].candidates,
                Some(Candidates::LegacyFunction)
            ));
        }
        for other in parse_dump(&dump())
            .unwrap()
            .iter()
            .filter(|integration| integration.stem != "click")
        {
            assert!(is_bridged(other), "{}", other.stem);
        }
    }

    #[test]
    fn a_click_sh_whose_click_command_was_edited_stays_wholly_on_the_bridge() {
        let click = click_of(&edited(
            "\"click\":\"click_at \\\"$id\\\"\"",
            "\"click\":\"click_at \\\"$id\\\" && echo clicked\"",
        ));
        assert!(is_bridged(&click));
    }

    #[test]
    fn each_command_of_the_fingerprint_is_checked() {
        for (action, edit) in [
            ("\"show_hints\":\"show_hints\"", "\"show_hints\":\"my_hints\""),
            ("\"no_text\":\"no_text\"", "\"no_text\":\"no_text; true\""),
            (
                "\"triple_click\":\"click_at \\\"$id\\\"\"",
                "\"triple_click\":\"click_at \\\"$id\\\" --foo\"",
            ),
            (
                "\"double_click\":\"click_at \\\"$id\\\"\"",
                "\"double_click\":\"my_click \\\"$id\\\"\"",
            ),
            (
                "\"right_click\":\"click_at \\\"$id\\\"\"",
                "\"right_click\":\"click_at 1\"",
            ),
        ] {
            assert!(is_bridged(&click_of(&edited(action, edit))), "{edit}");
        }
    }

    #[test]
    fn a_click_sh_without_its_hooks_or_under_another_name_stays_on_the_bridge() {
        assert!(is_bridged(&click_of(&edited(
            "\"hooks\":[\"candidates\",\"pick_box\",\"session_rewrite\"]",
            "\"hooks\":[\"candidates\",\"session_rewrite\"]"
        ))));
        assert!(is_bridged(&click_of(&edited(
            "\"hooks\":[\"candidates\",\"pick_box\",\"session_rewrite\"]",
            "\"hooks\":[\"pick_box\",\"session_rewrite\"]"
        ))));
        let renamed = dump().replacen(
            "\"file\":\"./integrations.d/click.sh\"",
            "\"file\":\"./integrations.d/mouse.sh\"",
            1,
        );
        let mouse = parse_dump(&renamed)
            .unwrap()
            .into_iter()
            .find(|integration| integration.stem == "mouse")
            .unwrap();
        assert!(is_bridged(&mouse));
    }
}
