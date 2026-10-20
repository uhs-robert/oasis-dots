//! The awk's word helpers: normalisation of spoken and recognised text into comparable words.
//!
//! Words are ASCII after `words_of`, so everything here works on bytes. The one non-ASCII input that still matters is
//! `lowered`: gawk's `tolower` in a UTF-8 locale maps U+0130 and U+212A to `i` and `k`, which then stay in the word.

/// The spoken fillers the awk skips when matching (`split("the a an ...")` in BEGIN). The test is on `normal_word`, so
/// "this" (singularised to "thi") is not one.
pub const FILLER_WORDS: [&str; 13] = [
    "the", "a", "an", "my", "this", "that", "please", "to", "of", "on", "in", "for", "it",
];

const DIGIT_WORDS: [&str; 10] = [
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
];

/// gawk's `tolower` under a UTF-8 locale, as far as it can reach `[a-z0-9]`. Every other non-ASCII letter lowers to
/// something the later `[^a-z0-9]` filter strips, as it does in its upper-case form.
fn lowered(text: &str) -> String {
    text.chars()
        .map(|c| match c {
            '\u{130}' => 'i',
            '\u{212a}' => 'k',
            _ => c.to_ascii_lowercase(),
        })
        .collect()
}

/// `lowered_alnum` followed by `gsub(/[^a-z0-9]+/, " ")` and `split(.., " ")`: the words of the text. Apostrophes are
/// deleted first, so "don't" is one word, "dont".
pub fn words_of(text: &str) -> Vec<String> {
    let mut words = Vec::new();
    let mut word = String::new();
    for c in lowered(text).chars().filter(|&c| c != '\'') {
        if c.is_ascii_lowercase() || c.is_ascii_digit() {
            word.push(c);
        } else if !word.is_empty() {
            words.push(std::mem::take(&mut word));
        }
    }
    if !word.is_empty() {
        words.push(word);
    }
    words
}

pub fn singular(word: &str) -> &str {
    if word.len() > 3 && word.ends_with('s') && !word.ends_with("ss") {
        &word[..word.len() - 1]
    } else {
        word
    }
}

/// Number words to digits, plurals to singular (the same normalisation as voxcmd's word matching).
pub fn normal_word(raw: &str) -> String {
    match DIGIT_WORDS.iter().position(|&name| name == raw) {
        Some(index) => (index + 1).to_string(),
        None => singular(raw).to_string(),
    }
}

pub fn is_filler(normal: &str) -> bool {
    normal.is_empty() || FILLER_WORDS.contains(&normal)
}

/// OCR look-alikes compare as one letter (`i`, `l` and `1`; `0` and `o`), for words of two or more characters. The awk
/// turns "ten" into the number 10 first and so keys it as "lo"; `normal_word` returning "10" reproduces that.
pub fn compare_key(word: &str) -> String {
    if word.len() < 2 {
        return word.to_string();
    }
    word.chars()
        .map(|c| match c {
            'i' | 'l' | '1' => 'l',
            '0' => 'o',
            _ => c,
        })
        .collect()
}

/// Whether the two words differ by at most one insertion, deletion or substitution.
pub fn within_one_edit(a: &str, b: &str) -> bool {
    let (a, b) = if a.len() < b.len() {
        (b.as_bytes(), a.as_bytes())
    } else {
        (a.as_bytes(), b.as_bytes())
    };
    if a.len() - b.len() > 1 {
        return false;
    }
    if a.len() == b.len() {
        return a.iter().zip(b).filter(|(x, y)| x != y).count() <= 1;
    }
    match a.iter().zip(b).position(|(x, y)| x != y) {
        Some(i) => a[i + 1..] == b[i..],
        None => true,
    }
}

/// Noise tolerance grows with the word: under five letters must match exactly, five allow one substitution, more one edit.
pub fn same_word(a: &str, b: &str) -> bool {
    if a == b {
        return true;
    }
    if a.len() < 5 || b.len() < 5 {
        return false;
    }
    if a.len() == 5 || b.len() == 5 {
        return a.len() == b.len() && within_one_edit(a, b);
    }
    within_one_edit(a, b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn words_are_ascii_alphanumeric_runs_with_apostrophes_deleted() {
        assert_eq!(words_of("Don't  Sign-In!"), ["dont", "sign", "in"]);
        assert_eq!(words_of("\u{130}STANBUL \u{212a}elvin"), ["istanbul", "kelvin"]);
        assert_eq!(words_of("caf\u{e9} \u{ff21}"), ["caf"]);
        assert!(words_of("| - ").is_empty());
    }

    #[test]
    fn normalisation_follows_the_awk() {
        assert_eq!(normal_word("ten"), "10");
        assert_eq!(compare_key("10"), "lo");
        assert_eq!(normal_word("settings"), "setting");
        assert_eq!(normal_word("class"), "class");
        assert!(!is_filler(&normal_word("this")));
        assert!(is_filler("the"));
        assert_eq!(compare_key("il1o0"), "llloo");
        assert_eq!(compare_key("l"), "l");
    }

    #[test]
    fn fuzziness_scales_with_length() {
        assert!(!same_word("save", "sive"));
        assert!(same_word("close", "clone"));
        assert!(!same_word("close", "closes"));
        assert!(same_word("cancel", "cancels"));
        assert!(!same_word("cancel", "cancl"));
        assert!(same_word("cancel", "cancell"));
        assert!(within_one_edit("abcd", "abd"));
        assert!(!within_one_edit("abcd", "acbd"));
    }
}
