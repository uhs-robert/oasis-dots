//! The input format of `click-ocr` as awk reads it: `#window` and `#strip` header lines, then tesseract's TSV rows.
//! awk treats every field as a "strnum": a number when the whole text looks like one, otherwise a string, and a
//! string wherever it is compared with another string. `Field` keeps both readings so comparisons come out as awk's.
use std::cmp::Ordering;

/// What awk's `isspace` skips around a number.
const BLANKS: [char; 6] = [' ', '\t', '\n', '\r', '\x0b', '\x0c'];

/// The longest number at the start of the text, as awk's string-to-number conversion reads it ("12abc" is 12, "0x10"
/// is 0). Returns the value and how much of the text it covered; the sign-prefixed `+inf` and `-nan` are numbers.
fn leading_number(text: &str) -> (f64, usize) {
    let bytes = text.as_bytes();
    let start = text.len() - text.trim_start_matches(BLANKS).len();
    let mut end = start;
    if matches!(bytes.get(end), Some(b'+' | b'-')) {
        end += 1;
        let rest = text[end..].to_ascii_lowercase();
        if rest.starts_with("inf") || rest.starts_with("nan") {
            let magnitude = if rest.starts_with("inf") {
                f64::INFINITY
            } else {
                f64::NAN
            };
            let negative = bytes[end - 1] == b'-';
            return (if negative { -magnitude } else { magnitude }, end + 3);
        }
    }
    let digits_from = end;
    while bytes.get(end).is_some_and(u8::is_ascii_digit) {
        end += 1;
    }
    let mut digits = end - digits_from;
    if bytes.get(end) == Some(&b'.') {
        let fraction_from = end + 1;
        let mut after = fraction_from;
        while bytes.get(after).is_some_and(u8::is_ascii_digit) {
            after += 1;
        }
        digits += after - fraction_from;
        if digits > 0 {
            end = after;
        }
    }
    if digits == 0 {
        return (0.0, 0);
    }
    if matches!(bytes.get(end), Some(b'e' | b'E')) {
        let mut after = end + 1;
        if matches!(bytes.get(after), Some(b'+' | b'-')) {
            after += 1;
        }
        let exponent_from = after;
        while bytes.get(after).is_some_and(u8::is_ascii_digit) {
            after += 1;
        }
        if after > exponent_from {
            end = after;
        }
    }
    (text[start..end].parse().unwrap_or(0.0), end)
}

/// A string used in arithmetic.
pub fn number_of(text: &str) -> f64 {
    leading_number(text).0
}

/// The number a text is when the whole of it looks like one (blanks allowed around it); None for "", "0x10", "inf",
/// "12abc".
pub fn awk_number(text: &str) -> Option<f64> {
    let (value, used) = leading_number(text);
    (used > 0 && text[used..].trim_matches(BLANKS).is_empty()).then_some(value)
}

/// An integer-valued number prints as an integer, anything else as `%.6g` (awk's CONVFMT); used where a number is
/// compared with a string.
fn number_text(value: f64) -> String {
    if value.fract() == 0.0 && value.abs() < 1e16 {
        format!("{}", value as i64)
    } else {
        format!("{value}")
    }
}

/// awk's `printf "%d"`: truncation toward zero.
pub fn int_text(value: f64) -> String {
    if value.is_nan() {
        return if value.is_sign_negative() { "-nan" } else { "nan" }.to_string();
    }
    if value.is_infinite() {
        return if value < 0.0 { "-inf" } else { "inf" }.to_string();
    }
    format!("{:.0}", value.trunc())
}

/// One awk value that came from text or arithmetic. `number` is Some when it compares as a number.
#[derive(Clone, Debug, PartialEq)]
pub struct Field {
    pub text: String,
    pub number: Option<f64>,
}

impl Field {
    pub fn from_text(text: &str) -> Self {
        Self {
            text: text.to_string(),
            number: awk_number(text),
        }
    }

    pub fn from_number(value: f64) -> Self {
        Self {
            text: number_text(value),
            number: Some(value),
        }
    }

    /// An uninitialised variable or a missing array element: "" that compares as 0.
    pub fn absent() -> Self {
        Self {
            text: String::new(),
            number: Some(0.0),
        }
    }

    /// The field in arithmetic.
    pub fn value(&self) -> f64 {
        number_of(&self.text)
    }

    /// awk's comparison: numeric when both sides are numbers, byte-wise on the text otherwise. None when a NaN is
    /// involved, which makes every comparison false.
    pub fn compare(&self, other: &Field) -> Option<Ordering> {
        match (self.number, other.number) {
            (Some(a), Some(b)) => a.partial_cmp(&b),
            _ => Some(self.text.as_bytes().cmp(other.text.as_bytes())),
        }
    }

    pub fn less(&self, other: &Field) -> bool {
        self.compare(other) == Some(Ordering::Less)
    }

    pub fn at_least(&self, other: &Field) -> bool {
        matches!(self.compare(other), Some(Ordering::Greater | Ordering::Equal))
    }

    pub fn greater(&self, other: &Field) -> bool {
        self.compare(other) == Some(Ordering::Greater)
    }
}

/// One input line, classified the way the awk's rules test it.
#[derive(Debug, PartialEq)]
pub enum Line<'a> {
    /// `#window gx gy gw gh iw ih`: the six numbers (missing ones are absent).
    Window([Field; 6]),
    /// `#strip i y0 own_top own_bottom`: y0, own_top and own_bottom.
    Strip([Field; 3]),
    /// A tesseract line box (level 4); it says which strip owns the words of that line.
    Block(Row<'a>),
    /// A tesseract word row (level 5).
    Word(Row<'a>),
    Other,
}

/// A tab-split row; `field(n)` is awk's `$n` (1-based, "" past the end).
#[derive(Debug, PartialEq)]
pub struct Row<'a> {
    fields: Vec<&'a str>,
}

impl Row<'_> {
    pub fn field(&self, n: usize) -> &str {
        self.fields.get(n - 1).copied().unwrap_or("")
    }

    pub fn number(&self, n: usize) -> f64 {
        number_of(self.field(n))
    }

    pub fn as_field(&self, n: usize) -> Field {
        Field::from_text(self.field(n))
    }
}

/// `split($0, w, " ")`: runs of blanks separate, leading and trailing ones are ignored.
fn header_fields(line: &str) -> Vec<&str> {
    line.split(BLANKS).filter(|part| !part.is_empty()).collect()
}

fn header_field(parts: &[&str], index: usize) -> Field {
    parts
        .get(index)
        .map_or_else(Field::absent, |text| Field::from_text(text))
}

pub fn parse_line(line: &str) -> Line<'_> {
    if line.starts_with("#window ") {
        let parts = header_fields(line);
        return Line::Window(std::array::from_fn(|i| header_field(&parts, i + 1)));
    }
    if line.starts_with("#strip ") {
        let parts = header_fields(line);
        return Line::Strip(std::array::from_fn(|i| header_field(&parts, i + 2)));
    }
    let row = Row {
        fields: line.split('\t').collect(),
    };
    match awk_number(row.field(1)) {
        Some(4.0) => Line::Block(row),
        Some(5.0) => Line::Word(row),
        _ => Line::Other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn numbers_are_read_as_awk_reads_them() {
        for (text, strnum, prefix) in [
            ("5", Some(5.0), 5.0),
            (" 5 ", Some(5.0), 5.0),
            ("+5", Some(5.0), 5.0),
            ("5.", Some(5.0), 5.0),
            (".5", Some(0.5), 0.5),
            ("5e0", Some(5.0), 5.0),
            ("1e", None, 1.0),
            ("12abc", None, 12.0),
            ("0x10", None, 0.0),
            ("inf", None, 0.0),
            ("", None, 0.0),
            ("-1", Some(-1.0), -1.0),
            ("96.842567", Some(96.842567), 96.842567),
        ] {
            assert_eq!(awk_number(text), strnum, "{text:?}");
            assert_eq!(number_of(text), prefix, "{text:?}");
        }
        assert_eq!(awk_number("+inf"), Some(f64::INFINITY));
        assert!(awk_number("-nan").is_some_and(f64::is_nan));
    }

    #[test]
    fn a_non_numeric_field_compares_as_a_string() {
        let forty = Field::from_number(40.0);
        assert!(Field::from_text("0x10").less(&forty));
        assert!(!Field::from_text("abc").less(&forty));
        assert!(Field::from_text("-1").less(&forty));
        assert!(Field::from_text("").less(&forty));
        assert!(!Field::from_text("9").greater(&Field::from_text("10")));
        assert!(Field::from_text("9").less(&Field::from_text("10")));
        assert!(Field::from_text("9a").greater(&Field::from_text("10")));
    }

    #[test]
    fn lines_are_classified_by_their_level_and_prefix() {
        assert!(matches!(parse_line("#window 1 2 3 4 5 6"), Line::Window(_)));
        assert!(matches!(parse_line("#strip 0 0 0 600"), Line::Strip(_)));
        assert!(matches!(parse_line("5\t1\t1"), Line::Word(_)));
        assert!(matches!(parse_line(" 4 \t1"), Line::Block(_)));
        assert!(matches!(parse_line("level\tpage_num"), Line::Other));
        assert!(matches!(parse_line("#window"), Line::Other));
        assert_eq!(int_text(-96.9), "-96");
    }
}
