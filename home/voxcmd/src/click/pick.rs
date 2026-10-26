//! Where on screen each click option is, for the numbered overlay: the port of click.sh's `pick_box` and the
//! `pick-boxes` command that wrapped it.
use serde_json::{Value, json};

/// The box of a candidate id `x,y,button,left,top,width,height`, as `read -r` splits it: seven fields, the last
/// taking the rest of the line (so a comma in it is part of the height and fails the number check). A line break ends
/// the id, as it ends what `read` takes. None when there is no height, or a part is not a number.
fn box_of(id: &str) -> Option<[Value; 4]> {
    let id = id.split('\n').next().unwrap_or_default();
    let mut fields = id.splitn(7, ',');
    let parts: Vec<&str> = fields.by_ref().skip(3).collect();
    // A height that is empty (or missing) is no box, as `[ -n "${height:-}" ]` decides.
    let [left, top, width, height] = parts[..] else {
        return None;
    };
    if height.is_empty() {
        return None;
    }
    let mut numbers = [Value::Null, Value::Null, Value::Null, Value::Null];
    for (slot, text) in numbers.iter_mut().zip([left, top, width, height]) {
        *slot = number(text)?;
    }
    Some(numbers)
}

/// jq's `tonumber` for what `echo "$left $top $width $height"` made of the parts: a plain decimal number, no spaces
/// (a space would have split the part in two).
fn number(text: &str) -> Option<Value> {
    if text.is_empty() || text.contains(' ') {
        return None;
    }
    if let Ok(whole) = text.parse::<i64>() {
        return Some(json!(whole));
    }
    let decimal = text.parse::<f64>().ok().filter(|value| value.is_finite())?;
    Some(json!(decimal))
}

/// `choices` (the JSON `[{id, label}, ...]` the picker shows) with each option's `box: [left, top, width, height]`
/// added, `ids` being the options' ids in the same order. None unless every option has a box and the lists match, so
/// that no box ever sits on another option and the text picker asks instead.
pub fn boxed_choices(choices_json: &str, ids: &[&str]) -> Option<String> {
    let Value::Array(choices) = serde_json::from_str(choices_json).ok()? else {
        return None;
    };
    if choices.len() != ids.len() {
        return None;
    }
    let boxed: Vec<Value> = choices
        .into_iter()
        .zip(ids)
        .map(|(choice, id)| {
            let Value::Object(mut fields) = choice else {
                return None;
            };
            fields.insert("box".to_string(), Value::Array(box_of(id)?.to_vec()));
            Some(Value::Object(fields))
        })
        .collect::<Option<_>>()?;
    Some(Value::Array(boxed).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn boxed(choices: &str, ids: &[&str]) -> Option<Value> {
        serde_json::from_str(&boxed_choices(choices, ids)?).ok()
    }

    #[test]
    fn an_id_places_its_box() {
        assert_eq!(
            box_of("150,75,left,100,50,60,20"),
            Some([json!(100), json!(50), json!(60), json!(20)])
        );
    }

    #[test]
    fn an_id_without_a_height_has_no_box() {
        assert_eq!(box_of("150,75,left"), None);
        assert_eq!(box_of("150,75,left,100,50,60"), None);
        assert_eq!(box_of("150,75,left,100,50,60,"), None);
        assert_eq!(box_of(""), None);
    }

    #[test]
    fn every_part_of_the_box_must_be_a_number() {
        assert_eq!(box_of("1,2,left,a,50,60,20"), None);
        assert_eq!(box_of("1,2,left,100,,60,20"), None);
        assert_eq!(
            box_of("1,2,left,100,50,60,20,5"),
            None,
            "the eighth field is part of the height"
        );
        assert_eq!(box_of("1,2,left,100,5 0,60,20"), None);
        assert_eq!(box_of("1,2,left,100,50,60,nan"), None);
        assert_eq!(box_of("1,2,left,100,50,60,inf"), None);
    }

    #[test]
    fn a_negative_box_is_a_box() {
        // A window on a monitor left of the origin.
        assert_eq!(
            box_of("-100,75,left,-200,50,60,20"),
            Some([json!(-200), json!(50), json!(60), json!(20)])
        );
    }

    #[test]
    fn only_the_first_line_of_an_id_is_read() {
        assert_eq!(
            box_of("1,2,left,3,4,5,6\n7,8"),
            Some([json!(3), json!(4), json!(5), json!(6)])
        );
    }

    #[test]
    fn the_choices_gain_their_boxes_in_order() {
        let choices = r#"[{"id":"0","label":"Next - top"},{"id":"1","label":"Next - bottom"}]"#;
        let ids = ["1,2,left,100,50,60,20", "3,4,left,300,200,70,22"];
        assert_eq!(
            boxed(choices, &ids),
            Some(json!([
                {"id": "0", "label": "Next - top", "box": [100, 50, 60, 20]},
                {"id": "1", "label": "Next - bottom", "box": [300, 200, 70, 22]},
            ]))
        );
    }

    #[test]
    fn one_option_without_a_box_sends_the_whole_pick_to_the_text_picker() {
        let choices = r#"[{"id":"0","label":"a"},{"id":"1","label":"b"}]"#;
        assert_eq!(boxed(choices, &["1,2,left,100,50,60,20", "3,4,left"]), None);
        assert_eq!(
            boxed(choices, &["1,2,left,100,50,60,20", "3,4,left,not,a,box,here"]),
            None
        );
    }

    #[test]
    fn a_count_that_differs_from_the_choices_or_choices_that_are_no_list_fail() {
        let choices = r#"[{"id":"0","label":"a"}]"#;
        assert_eq!(boxed(choices, &["1,2,left,1,2,3,4", "1,2,left,1,2,3,4"]), None);
        assert_eq!(boxed(choices, &[]), None);
        assert_eq!(boxed("not json", &["1,2,left,1,2,3,4"]), None);
        assert_eq!(boxed(r#"{"id":"0"}"#, &["1,2,left,1,2,3,4"]), None);
        assert_eq!(boxed(r#"["a"]"#, &["1,2,left,1,2,3,4"]), None);
    }
}
