//! spoken numbers, positions, ordinals, durations, times, days; format_at/length/due; `util speech`
//!
//! Transcripts arrive normalized: lowercase, no punctuation, so "1.5 hours" is "1 5 hours" and "3:30 p.m." is
//! "3 30 p m". Amounts are kept in thousandths so halves and quarters stay integer arithmetic. Behaviour follows the
//! bash `spoken-time.sh` and `spoken-position.sh` it replaces, quirks included, until the golden tests are changed.
use crate::cli::SpeechCommand;
use crate::exit::CliError;
use jiff::civil::{Date, Weekday};
use jiff::tz::{AmbiguousOffset, TimeZone};
use jiff::{Span, Timestamp};
use serde::Deserialize;
use std::path::PathBuf;

/// The clock every time function reads. `VOXCMD_NOW=<epoch seconds>` stands in for it in tests, so expectations do not
/// move with the day and hour.
pub struct Clock {
    pub now: i64,
    pub tz: TimeZone,
}

impl Clock {
    pub fn from_env() -> Result<Self, String> {
        let now = match std::env::var("VOXCMD_NOW") {
            Ok(value) if !value.is_empty() => value
                .parse::<i64>()
                .map_err(|_| format!("VOXCMD_NOW is not epoch seconds: {value:?}"))?,
            _ => Timestamp::now().as_second(),
        };
        Timestamp::from_second(now).map_err(|_| format!("VOXCMD_NOW is out of range: {now}"))?;
        Ok(Self {
            now,
            tz: TimeZone::system(),
        })
    }

    fn date_of(&self, epoch: i64) -> Option<Date> {
        Some(Timestamp::from_second(epoch).ok()?.to_zoned(self.tz.clone()).date())
    }

    pub fn today(&self) -> Date {
        self.date_of(self.now).expect("the clock holds a representable time")
    }

    /// The epoch of a local date and time, or none when the time does not exist (skipped by a clock change). A time
    /// that happens twice is its first occurrence.
    fn local_epoch(&self, date: Date, hour: i64, minute: i64) -> Option<i64> {
        let civil = date.at(i8::try_from(hour).ok()?, i8::try_from(minute).ok()?, 0, 0);
        let ambiguous = self.tz.to_ambiguous_timestamp(civil);
        match ambiguous.offset() {
            AmbiguousOffset::Gap { .. } => None,
            _ => Some(ambiguous.earlier().ok()?.as_second()),
        }
    }
}

fn number_word(word: &str) -> Option<i64> {
    Some(match word {
        "zero" => 0,
        "one" => 1,
        "two" => 2,
        "three" => 3,
        "four" => 4,
        "five" => 5,
        "six" => 6,
        "seven" => 7,
        "eight" => 8,
        "nine" => 9,
        "ten" => 10,
        "eleven" => 11,
        "twelve" => 12,
        "thirteen" => 13,
        "fourteen" => 14,
        "fifteen" => 15,
        "sixteen" => 16,
        "seventeen" => 17,
        "eighteen" => 18,
        "nineteen" => 19,
        "twenty" => 20,
        "thirty" => 30,
        "forty" => 40,
        "fifty" => 50,
        "sixty" => 60,
        "seventy" => 70,
        "eighty" => 80,
        "ninety" => 90,
        _ => return None,
    })
}

fn ordinal_word(word: &str) -> Option<i64> {
    Some(match word {
        "first" => 1,
        "second" => 2,
        "third" => 3,
        "fourth" => 4,
        "fifth" => 5,
        "sixth" => 6,
        "seventh" => 7,
        "eighth" => 8,
        "ninth" => 9,
        "tenth" => 10,
        "eleventh" => 11,
        "twelfth" => 12,
        "thirteenth" => 13,
        "fourteenth" => 14,
        "fifteenth" => 15,
        "sixteenth" => 16,
        "seventeenth" => 17,
        "eighteenth" => 18,
        "nineteenth" => 19,
        "twentieth" => 20,
        "thirtieth" => 30,
        "fortieth" => 40,
        "fiftieth" => 50,
        "sixtieth" => 60,
        "seventieth" => 70,
        "eightieth" => 80,
        "ninetieth" => 90,
        _ => return None,
    })
}

fn is_tens(value: i64) -> bool {
    (20..=90).contains(&value) && value % 10 == 0
}

fn is_digits(text: &str) -> bool {
    !text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit())
}

/// Bash's `read -r first second`: the first line, split at the first run of blanks; `second` keeps the rest, minus
/// trailing blanks.
fn read_first_second(text: &str) -> (&str, &str) {
    let line = text.split('\n').next().unwrap_or("");
    let blank = |c: char| c == ' ' || c == '\t';
    let line = line.trim_matches(blank);
    match line.find(blank) {
        Some(end) => (&line[..end], line[end..].trim_start_matches(blank)),
        None => (line, ""),
    }
}

/// The number a single word or a "tens ones" pair names when it is an ordinal ("second", "2nd", "twenty first"). A
/// digit ordinal needs its own suffix: "2th" and "11st" are not ordinals.
pub fn spoken_ordinal(text: &str) -> Option<i64> {
    let (first, second) = read_first_second(text);
    if first.is_empty() {
        return None;
    }
    if !second.is_empty() {
        if text != format!("{first} {second}") {
            return None;
        }
        let tens = number_word(first).filter(|&value| is_tens(value))?;
        let ones = ordinal_word(second).filter(|value| (1..=9).contains(value))?;
        return Some(tens + ones);
    }
    if let Some(value) = ordinal_word(first) {
        return Some(value);
    }
    let digits_end = first.find(|c: char| !c.is_ascii_digit())?;
    let (digits, suffix) = first.split_at(digits_end);
    if digits.is_empty() || !matches!(suffix, "st" | "nd" | "rd" | "th") {
        return None;
    }
    let number: i64 = digits.parse().ok()?;
    if number < 1 {
        return None;
    }
    let expected = match if (11..=13).contains(&(number % 100)) {
        0
    } else {
        number % 10
    } {
        1 => "st",
        2 => "nd",
        3 => "rd",
        _ => "th",
    };
    (suffix == expected).then_some(number)
}

/// The number digits, a number word or a "tens ones" pair name ("7", "seven", "twenty five").
pub fn spoken_cardinal(text: &str) -> Option<i64> {
    let (first, second) = read_first_second(text);
    if first.is_empty() {
        return None;
    }
    if !second.is_empty() {
        if text != format!("{first} {second}") {
            return None;
        }
        let tens = number_word(first).filter(|&value| is_tens(value))?;
        let ones = number_word(second).filter(|value| (1..=9).contains(value))?;
        return Some(tens + ones);
    }
    if is_digits(first) {
        return first.parse().ok();
    }
    number_word(first)
}

/// The position a phrase names, as a number or as an ordinal. Whether it exists is the caller's to check.
pub fn spoken_position(text: &str) -> Option<i64> {
    spoken_cardinal(text).or_else(|| spoken_ordinal(text))
}

/// Words of a phrase as bash's `read -ra` splits them: the first line, at blanks.
pub fn split_words(text: &str) -> Vec<&str> {
    text.split('\n')
        .next()
        .unwrap_or("")
        .split([' ', '\t'])
        .filter(|word| !word.is_empty())
        .collect()
}

/// `words[at]`, or "" past the end, like `${array[at]-}`.
fn word_at<'a>(words: &[&'a str], at: usize) -> &'a str {
    words.get(at).copied().unwrap_or("")
}

fn unit_seconds(word: &str) -> Option<i64> {
    match word {
        "s" | "sec" | "secs" | "second" | "seconds" => Some(1),
        "m" | "min" | "mins" | "minute" | "minutes" => Some(60),
        "h" | "hr" | "hrs" | "hour" | "hours" => Some(3600),
        _ => None,
    }
}

fn is_article(word: &str) -> bool {
    word == "a" || word == "an"
}

/// Reads an amount at `words[*at]` in thousandths and advances `at`: digits, "1 5" (1.5), number words ("twenty
/// five"), "a"/"an", "half (a|an)", "a quarter (of) (an)", and a trailing "and a half".
fn read_amount(words: &[&str], at: &mut usize) -> Option<i64> {
    let word = word_at(words, *at);
    let next = word_at(words, *at + 1);
    let mut milli;
    if is_digits(word) {
        milli = word.parse::<i64>().ok()?.checked_mul(1000)?;
        *at += 1;
        if is_digits(next) && next.len() <= 3 && unit_seconds(word_at(words, *at + 1)).is_some() {
            let fraction: i64 = format!("{next}000")[..3].parse().ok()?;
            milli += fraction;
            *at += 1;
        }
    } else if word == "half" {
        milli = 500;
        *at += 1;
        if is_article(word_at(words, *at)) {
            *at += 1;
        }
    } else if is_article(word) && next == "quarter" {
        milli = 250;
        *at += 2;
        if word_at(words, *at) == "of" {
            *at += 1;
        }
        if is_article(word_at(words, *at)) {
            *at += 1;
        }
    } else if is_article(word) && next == "half" {
        milli = 500;
        *at += 2;
    } else if is_article(word) {
        milli = 1000;
        *at += 1;
    } else {
        // One number word, or a tens word and a ones word ("twenty five"); "three thirty" stays two numbers.
        let mut value = number_word(word)?;
        *at += 1;
        if value >= 20 && number_word(next).is_some_and(|ones| (1..=9).contains(&ones)) {
            value += number_word(next)?;
            *at += 1;
        }
        milli = value * 1000;
    }
    if word_at(words, *at) == "and"
        && word_at(words, *at + 1) == "a"
        && word_at(words, *at + 2) == "half"
        && unit_seconds(word_at(words, *at + 3)).is_some()
    {
        milli += 500;
        *at += 3;
    }
    Some(milli)
}

/// The seconds a whole phrase names: "5 minutes", "90 seconds", "an hour and a half", "1 hour 30", "two and a half
/// minutes", "half an hour", "1 5 hours". None on anything left over.
pub fn parse_duration(text: &str) -> Option<i64> {
    let words = split_words(text);
    if words.is_empty() {
        return None;
    }
    let mut at = 0;
    let mut total_milli = 0i64;
    let mut last_unit: Option<i64> = None;
    while at < words.len() {
        if words[at] == "and"
            && let Some(unit) = last_unit
        {
            at += 1;
            // "an hour and a half": half of the unit just named
            if word_at(&words, at) == "a" && word_at(&words, at + 1) == "half" && word_at(&words, at + 2).is_empty() {
                total_milli += unit * 500;
                at += 2;
                continue;
            }
        }
        let amount_milli = read_amount(&words, &mut at)?;
        let unit = if let Some(unit) = unit_seconds(word_at(&words, at)) {
            at += 1;
            unit
        } else {
            // A bare number after a unit counts in the next one down: "1 hour 30", "2 minutes 15".
            last_unit.filter(|&previous| previous > 1 && word_at(&words, at).is_empty())? / 60
        };
        total_milli += amount_milli * unit;
        last_unit = Some(unit);
    }
    Some((total_milli + 500) / 1000)
}

fn weekday_of(word: &str) -> Option<Weekday> {
    Some(match word {
        "monday" => Weekday::Monday,
        "tuesday" => Weekday::Tuesday,
        "wednesday" => Weekday::Wednesday,
        "thursday" => Weekday::Thursday,
        "friday" => Weekday::Friday,
        "saturday" => Weekday::Saturday,
        "sunday" => Weekday::Sunday,
        _ => return None,
    })
}

/// The date a day word names ("today", "tomorrow", "friday", "next friday"); a bare weekday may be today, "next
/// friday" never is.
fn day_date(word: &str, clock: &Clock) -> Option<Date> {
    let today = clock.today();
    match word {
        "today" => Some(today),
        "tomorrow" => today.tomorrow().ok(),
        _ => {
            let weekday = word.strip_prefix("next ").unwrap_or(word);
            let target = weekday_of(weekday)?.to_monday_one_offset() as i64;
            let mut ahead = (7 + target - today.weekday().to_monday_one_offset() as i64) % 7;
            if weekday != word && ahead == 0 {
                ahead = 7;
            }
            today.checked_add(Span::new().days(ahead)).ok()
        }
    }
}

/// The date a day word names, or none for anything else.
pub fn parse_day(text: &str, clock: &Clock) -> Option<Date> {
    match text {
        "today" | "tomorrow" => day_date(text, clock),
        _ => weekday_of(text.strip_prefix("next ").unwrap_or(text)).and(day_date(text, clock)),
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Anchor {
    /// The next time the clock reads that: today, or tomorrow once the time has passed.
    Next,
    /// A time already past today stays today, for converting a time rather than scheduling one.
    Today,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Day {
    Today,
    Tomorrow,
}

/// The epoch a clock time names: "3 pm", "3 30 p m", "15 30", "three thirty pm", "noon", "9 am tomorrow", "tomorrow
/// at 7", "friday at 9 am", read in the clock's zone. A weekday name ("friday", "next friday") is that day's next
/// occurrence, a week out when it is today and the time has passed. With no am or pm, whichever of the two comes next.
pub fn parse_clock(text: &str, anchor: Anchor, clock: &Clock) -> Option<i64> {
    let words = split_words(text);
    let mut clock_words: Vec<&str> = Vec::new();
    let mut day = None;
    let mut weekday: Option<&str> = None;
    let mut weekday_prefix = false;
    let mut meridiem: Option<&str> = None;
    for (index, &word) in words.iter().enumerate() {
        match word {
            "at" | "o" | "oh" | "oclock" | "clock" | "the" | "this" => {}
            // Only before a weekday, so "9 am next in tokyo" keeps reading as it did.
            "on" | "next" => {
                let before_weekday = weekday_of(word_at(&words, index + 1)).is_some();
                if !before_weekday {
                    clock_words.push(word);
                }
                if word == "next" && before_weekday {
                    weekday_prefix = true;
                }
            }
            "today" => day = Some(Day::Today),
            "tomorrow" => day = Some(Day::Tomorrow),
            "monday" | "tuesday" | "wednesday" | "thursday" | "friday" | "saturday" | "sunday" => weekday = Some(word),
            "tonight" | "afternoon" | "evening" | "pm" | "p" => meridiem = Some("pm"),
            "am" | "a" | "morning" => meridiem = Some("am"),
            "m" => {}
            "noon" | "midday" => {
                clock_words.push("12");
                meridiem = Some("pm");
            }
            "midnight" => {
                clock_words.push("12");
                meridiem = Some("am");
            }
            _ => {
                let bytes = word.as_bytes();
                let digit_then_meridiem = bytes.len() >= 3
                    && bytes[bytes.len() - 3].is_ascii_digit()
                    && (word.ends_with("am") || word.ends_with("pm"));
                if digit_then_meridiem {
                    clock_words.push(&word[..word.len() - 2]);
                    meridiem = Some(if word.ends_with("am") { "am" } else { "pm" });
                } else {
                    clock_words.push(word);
                }
            }
        }
    }
    // Hour, then minutes, each digits or number words ("three thirty", "seven oh five").
    if clock_words.is_empty() {
        return None;
    }
    let mut at = 0;
    let mut hour;
    let mut minute = 0;
    if clock_words[0].len() >= 3 && clock_words[0].len() <= 4 && is_digits(clock_words[0]) {
        let number: i64 = clock_words[0].parse().ok()?;
        hour = number / 100;
        minute = number % 100;
        at = 1;
    } else {
        let amount = read_amount(&clock_words, &mut at)?;
        if amount % 1000 != 0 {
            return None;
        }
        hour = amount / 1000;
        if at < clock_words.len() {
            let amount = read_amount(&clock_words, &mut at)?;
            if amount % 1000 != 0 {
                return None;
            }
            minute = amount / 1000;
        }
    }
    if at != clock_words.len() || hour > 23 || minute > 59 {
        return None;
    }
    if let Some(meridiem) = meridiem {
        if !(1..=12).contains(&hour) {
            return None;
        }
        hour %= 12;
        if meridiem == "pm" {
            hour += 12;
        }
    }
    let today = clock.today();
    let mut bases = [today, today.tomorrow().ok()?];
    if let Some(weekday) = weekday {
        if day.is_some() {
            return None;
        }
        let name = if weekday_prefix {
            format!("next {weekday}")
        } else {
            weekday.to_string()
        };
        let base = day_date(&name, clock)?;
        bases = [base, base.checked_add(Span::new().days(7)).ok()?];
    } else if anchor != Anchor::Next && day.is_none() {
        day = Some(Day::Today);
    }
    // No am or pm on a 1 to 12 hour: the sooner of the morning and evening time.
    let hours = if meridiem.is_none() && (1..=12).contains(&hour) {
        vec![hour % 12, hour % 12 + 12]
    } else {
        vec![hour]
    };
    let wanted_day = match day {
        Some(Day::Today) => Some(today),
        Some(Day::Tomorrow) => Some(today.tomorrow().ok()?),
        None => None,
    };
    let mut first = None;
    for base in bases {
        if wanted_day.is_some_and(|wanted| wanted != base) {
            continue;
        }
        for &hour in &hours {
            let candidate = clock.local_epoch(base, hour, minute)?;
            first = first.or(Some(candidate));
            if candidate > clock.now || day == Some(Day::Tomorrow) {
                return Some(candidate);
            }
        }
    }
    if anchor == Anchor::Today { first } else { None }
}

/// "1 hour 30 minutes", "45 seconds"; nothing for zero.
pub fn format_length(total: i64) -> String {
    let hours = total / 3600;
    let minutes = total % 3600 / 60;
    let seconds = total % 60;
    let part = |count: i64, unit: &str| format!("{count} {unit}{}", if count == 1 { "" } else { "s" });
    let mut parts = Vec::new();
    if hours != 0 {
        parts.push(part(hours, "hour"));
    }
    if minutes != 0 {
        parts.push(part(minutes, "minute"));
    }
    if seconds != 0 {
        parts.push(part(seconds, "second"));
    }
    parts.join(" ")
}

#[derive(Deserialize)]
struct ClockSettings {
    time_format: Option<serde_json::Value>,
}

/// Whether the bar's Settings > Clock shows 12-hour time, the way its TimeFormat reads it: "locale" is 12-hour when
/// the locale's time format has an AM/PM field.
pub fn clock_is_twelve_hour() -> bool {
    let state_home = match std::env::var_os("XDG_STATE_HOME").filter(|value| !value.is_empty()) {
        Some(dir) => PathBuf::from(dir),
        None => PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state"),
    };
    let setting = std::fs::read_to_string(state_home.join("quickshell/clock.json"))
        .ok()
        .and_then(|text| serde_json::from_str::<ClockSettings>(&text).ok())
        .and_then(|settings| settings.time_format)
        .and_then(|value| value.as_str().map(str::to_string));
    match setting.as_deref() {
        Some("12h") => true,
        Some("24h") => false,
        _ => locale_has_am_pm(),
    }
}

fn locale_has_am_pm() -> bool {
    let Ok(output) = std::process::Command::new("locale").arg("t_fmt").output() else {
        return false;
    };
    let format = String::from_utf8_lossy(&output.stdout);
    format
        .split('%')
        .skip(1)
        .any(|conversion| conversion.starts_with(['p', 'P', 'r', 'I']))
}

fn short_weekday(weekday: Weekday) -> &'static str {
    ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][weekday.to_monday_zero_offset() as usize]
}

fn short_month(month: i8) -> &'static str {
    [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ][month as usize - 1]
}

/// "3:47pm", "tomorrow 9:00am", "Thu 9:00am" within the week, else "Oct 20 9:00am"; 24-hour as "15:47" when the
/// clock is not 12-hour.
pub fn format_due(due: i64, clock: &Clock, twelve_hour: bool) -> Option<String> {
    let moment = Timestamp::from_second(due).ok()?.to_zoned(clock.tz.clone());
    let due_day = moment.date();
    let today = clock.today();
    let day = if due_day == today {
        String::new()
    } else if due_day == today.tomorrow().ok()? {
        "tomorrow ".to_string()
    } else if due_day < today.checked_add(Span::new().days(7)).ok()? {
        format!("{} ", short_weekday(due_day.weekday()))
    } else {
        format!("{} {} ", short_month(due_day.month()), due_day.day())
    };
    let (hour, minute) = (moment.hour(), moment.minute());
    let time = if twelve_hour {
        let suffix = if hour < 12 { "am" } else { "pm" };
        format!("{}:{minute:02}{suffix}", if hour % 12 == 0 { 12 } else { hour % 12 })
    } else {
        format!("{hour:02}:{minute:02}")
    };
    Some(format!("{day}{time}"))
}

/// "at 3:47pm" today, "tomorrow 9:00am" otherwise: a day reads wrong after "at".
pub fn format_at(due: i64, clock: &Clock, twelve_hour: bool) -> Option<String> {
    let when = format_due(due, clock, twelve_hour)?;
    Some(if when.starts_with(|c: char| c.is_ascii_digit()) {
        format!("at {when}")
    } else {
        when
    })
}

/// The seconds of the longest leading run of words that reads as a duration, and the words after it joined by single
/// spaces. None when no run does or it is zero seconds; a zero run does not fall back to a shorter one.
pub fn split_duration(text: &str) -> Option<(i64, String)> {
    let words = split_words(text);
    let (count, seconds) = (1..=words.len())
        .rev()
        .find_map(|count| parse_duration(&words[..count].join(" ")).map(|seconds| (count, seconds)))?;
    (seconds > 0).then(|| (seconds, words[count..].join(" ")))
}

/// `voxcmd util speech ...`: prints the value; exit 1 when the words do not parse.
pub fn run(command: SpeechCommand) -> Result<String, CliError> {
    let name = |operation: &str| format!("util speech {operation}");
    let clock = |operation: &str| Clock::from_env().map_err(|message| CliError::usage(&name(operation), message));
    let whole_number = |operation: &str, text: &str| {
        text.trim()
            .parse::<i64>()
            .map_err(|_| CliError::failed(&name(operation), format!("not a whole number: {text:?}")))
    };
    let unparsed =
        |operation: &str, what: &str, text: &str| CliError::failed(&name(operation), format!("{text:?} is not {what}"));
    match command {
        SpeechCommand::FormatLength { seconds } => Ok(format_length(whole_number("format-length", &seconds)?)),
        SpeechCommand::FormatDue { epoch } => {
            let due = whole_number("format-due", &epoch)?;
            format_due(due, &clock("format-due")?, clock_is_twelve_hour())
                .ok_or_else(|| unparsed("format-due", "a time that can be shown", &epoch))
        }
        SpeechCommand::FormatAt { epoch } => {
            let due = whole_number("format-at", &epoch)?;
            format_at(due, &clock("format-at")?, clock_is_twelve_hour())
                .ok_or_else(|| unparsed("format-at", "a time that can be shown", &epoch))
        }
        SpeechCommand::ParseTime { today, words } => {
            let text = words.join(" ");
            let anchor = if today { Anchor::Today } else { Anchor::Next };
            parse_clock(&text, anchor, &clock("parse-time")?)
                .map(|epoch| epoch.to_string())
                .ok_or_else(|| unparsed("parse-time", "a clock time", &text))
        }
        SpeechCommand::ParseDuration { words } => {
            let text = words.join(" ");
            parse_duration(&text)
                .map(|seconds| seconds.to_string())
                .ok_or_else(|| unparsed("parse-duration", "a duration", &text))
        }
        SpeechCommand::SplitDuration { words } => {
            let text = words.join(" ");
            // The trailing space with an empty label is bash's `echo "$seconds ${label}"`.
            split_duration(&text)
                .map(|(seconds, label)| format!("{seconds} {label}"))
                .ok_or_else(|| unparsed("split-duration", "led by a duration", &text))
        }
        SpeechCommand::ParseDay { words } => {
            let text = words.join(" ");
            parse_day(&text, &clock("parse-day")?)
                .map(|date| date.to_string())
                .ok_or_else(|| unparsed("parse-day", "a day", &text))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Wednesday 2026-10-14 15:30 in New York.
    fn wednesday_afternoon() -> Clock {
        Clock {
            now: 1_792_006_200,
            tz: TimeZone::get("America/New_York").unwrap(),
        }
    }

    fn at(clock: &Clock, text: &str, anchor: Anchor) -> Option<String> {
        let epoch = parse_clock(text, anchor, clock)?;
        let moment = Timestamp::from_second(epoch).ok()?.to_zoned(clock.tz.clone());
        Some(moment.strftime("%F %H:%M").to_string())
    }

    #[test]
    fn durations_read_halves_quarters_and_trailing_units() {
        assert_eq!(parse_duration("an hour and a half"), Some(5400));
        assert_eq!(parse_duration("two and a half minutes"), Some(150));
        assert_eq!(parse_duration("a quarter of an hour"), Some(900));
        assert_eq!(parse_duration("1 5 hours"), Some(5400));
        assert_eq!(parse_duration("1 hour 30"), Some(5400));
        assert_eq!(parse_duration("twenty five minutes"), Some(1500));
        assert_eq!(parse_duration("90"), None);
        assert_eq!(parse_duration("5 minutes banana"), None);
        assert_eq!(parse_duration(""), None);
    }

    #[test]
    fn a_phrase_splits_into_its_leading_duration_and_a_label() {
        assert_eq!(
            split_duration("5 minutes for the pasta"),
            Some((300, "for the pasta".to_string()))
        );
        assert_eq!(split_duration("five minutes pasta"), Some((300, "pasta".to_string())));
        assert_eq!(
            split_duration("twenty five minutes to call the bank"),
            Some((1500, "to call the bank".to_string()))
        );
        assert_eq!(
            split_duration("half an hour for the oven"),
            Some((1800, "for the oven".to_string()))
        );
        assert_eq!(split_duration("  5   minutes   tea  "), Some((300, "tea".to_string())));
    }

    #[test]
    fn the_longest_leading_duration_wins() {
        // "an hour" parses alone, but so does the whole run.
        assert_eq!(
            split_duration("an hour and a half for the roast"),
            Some((5400, "for the roast".to_string()))
        );
        assert_eq!(split_duration("1 hour 30 minutes tea"), Some((5400, "tea".to_string())));
        // A bare number after a unit counts in the next unit down, so "30" is part of the duration.
        assert_eq!(split_duration("1 hour 30"), Some((5400, "".to_string())));
        assert_eq!(split_duration("2 minutes 15 tea"), Some((135, "tea".to_string())));
        // "and a half" only follows a unit, so "5 minutes and" leaves "and" in the label.
        assert_eq!(split_duration("5 minutes and tea"), Some((300, "and tea".to_string())));
    }

    #[test]
    fn a_duration_alone_leaves_an_empty_label() {
        assert_eq!(split_duration("an hour and a half"), Some((5400, "".to_string())));
        assert_eq!(split_duration("90 seconds"), Some((90, "".to_string())));
    }

    #[test]
    fn a_phrase_not_led_by_a_duration_does_not_split() {
        assert_eq!(split_duration("the pasta in 5 minutes"), None);
        assert_eq!(split_duration("banana"), None);
        assert_eq!(split_duration("90"), None);
        assert_eq!(split_duration(""), None);
        assert_eq!(split_duration("   "), None);
    }

    #[test]
    fn a_zero_duration_fails_without_trying_a_shorter_prefix() {
        assert_eq!(split_duration("0 seconds tea"), None);
        assert_eq!(split_duration("zero minutes"), None);
    }

    #[test]
    fn a_clock_time_without_am_or_pm_is_whichever_comes_next() {
        let clock = wednesday_afternoon();
        assert_eq!(at(&clock, "3 pm", Anchor::Next).as_deref(), Some("2026-10-15 15:00"));
        assert_eq!(at(&clock, "4", Anchor::Next).as_deref(), Some("2026-10-14 16:00"));
        assert_eq!(at(&clock, "noon", Anchor::Next).as_deref(), Some("2026-10-15 12:00"));
        assert_eq!(at(&clock, "9 am", Anchor::Today).as_deref(), Some("2026-10-14 09:00"));
        assert_eq!(
            at(&clock, "three thirty pm", Anchor::Next).as_deref(),
            Some("2026-10-15 15:30")
        );
        assert_eq!(at(&clock, "13 pm", Anchor::Next), None);
    }

    #[test]
    fn weekdays_are_the_next_occurrence_and_never_clash_with_a_day_word() {
        let clock = wednesday_afternoon();
        assert_eq!(
            at(&clock, "friday at 9 am", Anchor::Next).as_deref(),
            Some("2026-10-16 09:00")
        );
        assert_eq!(
            at(&clock, "wednesday at 9 am", Anchor::Next).as_deref(),
            Some("2026-10-21 09:00")
        );
        assert_eq!(
            at(&clock, "wednesday at 11 pm", Anchor::Next).as_deref(),
            Some("2026-10-14 23:00")
        );
        assert_eq!(at(&clock, "tomorrow friday at 3", Anchor::Next), None);
        assert_eq!(at(&clock, "9 am next in tokyo", Anchor::Next), None);
        assert_eq!(
            parse_day("next wednesday", &clock).map(|d| d.to_string()).as_deref(),
            Some("2026-10-21")
        );
        assert_eq!(
            parse_day("wednesday", &clock).map(|d| d.to_string()).as_deref(),
            Some("2026-10-14")
        );
        assert_eq!(parse_day("banana", &clock), None);
    }

    #[test]
    fn a_time_the_clock_skips_does_not_parse() {
        let clock = Clock {
            now: 1_772_931_600,
            tz: TimeZone::get("America/New_York").unwrap(),
        };
        assert_eq!(at(&clock, "tomorrow at 2 30 am", Anchor::Next), None);
        assert_eq!(
            at(&clock, "tomorrow at 3 30 am", Anchor::Next).as_deref(),
            Some("2026-03-08 03:30")
        );
    }

    #[test]
    fn positions_take_numbers_words_and_ordinals() {
        assert_eq!(spoken_position("twenty five"), Some(25));
        assert_eq!(spoken_position("twenty first"), Some(21));
        assert_eq!(spoken_position("13th"), Some(13));
        assert_eq!(spoken_position("2th"), None);
        assert_eq!(spoken_position("11st"), None);
        assert_eq!(spoken_ordinal("two"), None);
        assert_eq!(spoken_cardinal("second"), None);
    }

    #[test]
    fn lengths_and_due_times_read_for_a_person() {
        assert_eq!(format_length(5400), "1 hour 30 minutes");
        assert_eq!(format_length(61), "1 minute 1 second");
        assert_eq!(format_length(0), "");
        let clock = wednesday_afternoon();
        assert_eq!(format_due(1_792_009_620, &clock, true).as_deref(), Some("4:27pm"));
        assert_eq!(format_at(1_792_009_620, &clock, true).as_deref(), Some("at 4:27pm"));
        assert_eq!(
            format_at(1_792_009_620 + 86_400, &clock, false).as_deref(),
            Some("tomorrow 16:27")
        );
        assert_eq!(
            format_due(1_792_009_620 + 3 * 86_400, &clock, true).as_deref(),
            Some("Sat 4:27pm")
        );
        assert_eq!(
            format_due(1_792_009_620 + 10 * 86_400, &clock, true).as_deref(),
            Some("Oct 24 4:27pm")
        );
    }
}
