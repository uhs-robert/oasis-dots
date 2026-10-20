//! Finds the on-screen text a spoken click target names and maps it to global pointer coordinates: the port of
//! `click-match.awk`. Feed it `click-ocr`'s lines one at a time, then `finish`. The awk's globals are fields and its
//! functions methods of the same names, so the two read side by side; the arithmetic keeps the awk's operation order
//! (f64, left to right), because a different grouping moves a pixel.
use super::ocr_format::{Field, Line, Row, int_text, number_of, parse_line};
use super::words::{compare_key, is_filler, normal_word, same_word, words_of};
use std::collections::{HashMap, HashSet};

/// Confidence floors: a word under `MIN_CONF` is dropped unless it may be spoken, one under `LOW_CONF` always is.
pub const MIN_CONF: f64 = 60.0;
pub const LOW_CONF: f64 = 40.0;
/// Labels longer than this many characters are cut to `LABEL_KEEP` and an ellipsis.
const LABEL_LIMIT: usize = 48;
const LABEL_KEEP: usize = 45;

#[derive(Clone, Copy, Debug)]
pub struct Options {
    /// `CLICK_SPANS`: skip whole-run matching and search each run for sub-spans.
    pub spans_only: bool,
    /// `-v explain=1`: collect the trace.
    pub explain: bool,
    pub min_conf: f64,
    pub low_conf: f64,
}

impl Options {
    pub fn new(spans_only: bool, explain: bool) -> Self {
        Self {
            spans_only,
            explain,
            min_conf: MIN_CONF,
            low_conf: LOW_CONF,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Candidate {
    pub x: i64,
    pub y: i64,
    pub match_text: String,
    pub label: String,
    pub left: i64,
    pub top: i64,
    pub width: i64,
    pub height: i64,
}

impl Candidate {
    /// The id every consumer parses: `x,y,button,left,top,width,height`.
    #[allow(dead_code, reason = "used by the screen_text provider from 2.5c")]
    pub fn id(&self, button: &str) -> String {
        format!(
            "{},{},{button},{},{},{},{}",
            self.x, self.y, self.left, self.top, self.width, self.height
        )
    }

    /// The awk's output line (without the newline).
    pub fn tsv(&self) -> String {
        format!(
            "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            self.x, self.y, self.match_text, self.label, self.left, self.top, self.width, self.height
        )
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Pass {
    Whole,
    Spans,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Kind {
    Word,
    Joined,
    Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum TraceEvent {
    Pass(Pass),
    /// A word the confidence floor dropped that resembles a spoken word.
    Drop {
        conf: String,
        text: String,
        x: i64,
        y: i64,
        reason: String,
    },
    /// A run holding a word that is, resembles or nearly equals a spoken word, and what became of it.
    Run {
        id: usize,
        words: String,
        outcome: String,
    },
    /// A candidate stored from that run.
    Cand {
        run_id: usize,
        x: i64,
        y: i64,
        kind: Kind,
        match_text: String,
    },
}

impl TraceEvent {
    /// The awk's `~...` line (without the newline).
    pub fn tsv(&self) -> String {
        match self {
            Self::Pass(pass) => format!("~pass\t{}", if *pass == Pass::Spans { "spans" } else { "whole" }),
            Self::Drop {
                conf,
                text,
                x,
                y,
                reason,
            } => {
                format!("~drop\t{}\t{text}\t{x}\t{y}\t{reason}", int_text(number_of(conf)))
            }
            Self::Run { id, words, outcome } => format!("~run\t{id}\t{words}\t{outcome}"),
            Self::Cand {
                run_id,
                x,
                y,
                kind,
                match_text,
            } => {
                let kind = match kind {
                    Kind::Word => "word",
                    Kind::Joined => "joined",
                    Kind::Span => "span",
                };
                format!("~cand\t{run_id}\t{x}\t{y}\t{kind}\t{match_text}")
            }
        }
    }
}

/// The awk dies when a candidate is stored with a zero image size (or a zero window size for the hint).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum MatchError {
    DivisionByZero,
}

impl std::fmt::Display for MatchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("division by zero attempted")
    }
}

pub struct Output {
    /// In reading order, labels made unique; empty when the awk would have died.
    pub candidates: Vec<Candidate>,
    /// Everything traced before the end, also when the awk died.
    pub trace: Vec<TraceEvent>,
    pub error: Option<MatchError>,
}

type Fallible<T> = Result<T, MatchError>;

fn divide(a: f64, b: f64) -> Fallible<f64> {
    if b == 0.0 {
        Err(MatchError::DivisionByZero)
    } else {
        Ok(a / b)
    }
}

/// Nearest integer, half away from zero.
fn round(v: f64) -> f64 {
    if v < 0.0 {
        -(-v + 0.5).trunc()
    } else {
        (v + 0.5).trunc()
    }
}

/// One word of the run being built.
struct RunWord {
    skip: bool,
    low: bool,
    conf: String,
    raw: String,
    key: String,
    norm: String,
    left: Field,
    top: f64,
    right: f64,
    bottom: f64,
}

/// One word of the tesseract line being built (before `flush_line` cuts it into runs).
struct LineWord {
    text: String,
    low: bool,
    conf: String,
    left: Field,
    top: f64,
    width: Field,
    height: Field,
}

struct Found {
    candidate: Candidate,
    hint: String,
}

pub struct Matcher {
    options: Options,
    error: Option<MatchError>,
    trace: Vec<TraceEvent>,
    // The spoken target.
    spoken_all_n: usize,
    spoken_words: String,
    spoken_joined: String,
    spoken_filler: HashSet<String>,
    spoken_raw: Vec<String>,
    spoken_key: Vec<String>,
    // Window and strip.
    gx: f64,
    gy: f64,
    gw: f64,
    gh: f64,
    iw: f64,
    ih: f64,
    strip_y0: Field,
    own_top: Field,
    own_bottom: Field,
    last_key: String,
    line_owned: HashMap<String, bool>,
    line: Vec<LineWord>,
    // The run.
    run: Vec<RunWord>,
    run_text: String,
    run_seq: usize,
    used: HashSet<usize>,
    // 0-based inclusive indexes of the matched span; None until set.
    first: Option<usize>,
    last: Option<usize>,
    span_first: usize,
    span_last: usize,
    span_exact: bool,
    found: Vec<Found>,
}

impl Matcher {
    /// The BEGIN block.
    pub fn new(target: &str, options: Options) -> Self {
        let mut matcher = Self {
            options,
            error: None,
            trace: Vec::new(),
            spoken_all_n: 0,
            spoken_words: String::new(),
            spoken_joined: String::new(),
            spoken_filler: HashSet::new(),
            spoken_raw: Vec::new(),
            spoken_key: Vec::new(),
            gx: 0.0,
            gy: 0.0,
            gw: 0.0,
            gh: 0.0,
            iw: 0.0,
            ih: 0.0,
            strip_y0: Field::absent(),
            own_top: Field::absent(),
            own_bottom: Field::absent(),
            last_key: String::new(),
            line_owned: HashMap::new(),
            line: Vec::new(),
            run: Vec::new(),
            run_text: String::new(),
            run_seq: 0,
            used: HashSet::new(),
            first: None,
            last: None,
            span_first: 0,
            span_last: 0,
            span_exact: false,
            found: Vec::new(),
        };
        if options.explain {
            matcher.trace.push(TraceEvent::Pass(if options.spans_only {
                Pass::Spans
            } else {
                Pass::Whole
            }));
        }
        for part in words_of(target) {
            matcher.spoken_all_n += 1;
            if !matcher.spoken_words.is_empty() {
                matcher.spoken_words.push(' ');
            }
            matcher.spoken_words.push_str(&part);
            let normal = normal_word(&part);
            matcher.spoken_joined.push_str(&normal);
            if is_filler(&normal) {
                matcher.spoken_filler.insert(normal);
                continue;
            }
            matcher.spoken_key.push(compare_key(&normal));
            matcher.spoken_raw.push(part);
        }
        if !matcher.spoken_raw.is_empty() {
            matcher.spoken_joined = compare_key(&matcher.spoken_joined);
        }
        matcher
    }

    fn spoken_n(&self) -> usize {
        self.spoken_raw.len()
    }

    /// The main rules, for one input line (no newline).
    pub fn feed(&mut self, input: &str) {
        if self.spoken_n() == 0 || self.error.is_some() {
            return;
        }
        let result = match parse_line(input) {
            Line::Window(numbers) => {
                [self.gx, self.gy, self.gw, self.gh, self.iw, self.ih] = numbers.map(|field| field.value());
                Ok(())
            }
            Line::Strip([y0, own_top, own_bottom]) => self.on_strip(y0, own_top, own_bottom),
            Line::Block(row) => {
                let centre = row.number(8) + self.strip_y0.value() + row.number(10) / 2.0;
                let owned = self.owns(centre);
                self.line_owned.insert(Self::line_id(&row), owned);
                Ok(())
            }
            Line::Word(row) => self.on_word(&row),
            Line::Other => Ok(()),
        };
        if let Err(error) = result {
            self.error = Some(error);
        }
    }

    /// The END block.
    pub fn finish(mut self) -> Output {
        if self.spoken_n() > 0
            && self.error.is_none()
            && let Err(error) = self.flush_line()
        {
            self.error = Some(error);
        }
        let mut candidates = Vec::new();
        if self.error.is_none() && self.spoken_n() > 0 {
            let order = self.sort_found();
            let labels: Vec<String> = self
                .found
                .iter()
                .map(|f| format!("{} - {}", f.candidate.label, f.hint))
                .collect();
            let mut seen: HashMap<&String, usize> = HashMap::new();
            for index in order {
                let label = &labels[index];
                let total = labels.iter().filter(|other| *other == label).count();
                let nth = seen.entry(label).or_insert(0);
                *nth += 1;
                let mut candidate = self.found[index].candidate.clone();
                candidate.label = if total > 1 {
                    format!("{label} #{nth}")
                } else {
                    label.clone()
                };
                candidates.push(candidate);
            }
        }
        Output {
            candidates,
            trace: self.trace,
            error: self.error,
        }
    }

    fn line_id(row: &Row) -> String {
        format!("{}\x1c{}\x1c{}", row.field(3), row.field(4), row.field(5))
    }

    fn owns(&self, centre: f64) -> bool {
        let centre = Field::from_number(centre);
        centre.at_least(&self.own_top) && centre.less(&self.own_bottom)
    }

    fn on_strip(&mut self, y0: Field, own_top: Field, own_bottom: Field) -> Fallible<()> {
        self.flush_line()?;
        self.strip_y0 = y0;
        self.own_top = own_top;
        self.own_bottom = own_bottom;
        self.last_key.clear();
        self.line_owned.clear();
        Ok(())
    }

    fn on_word(&mut self, row: &Row) -> Fallible<()> {
        let text = row.field(12).trim_matches(' ').to_string();
        if text.is_empty() {
            return Ok(());
        }
        let conf = row.as_field(11);
        let low_floor = Field::from_number(self.options.low_conf);
        let min_floor = Field::from_number(self.options.min_conf);
        let dropped = conf.less(&low_floor) || (conf.less(&min_floor) && !self.may_be_spoken(&text));
        let top = row.number(8) + self.strip_y0.value();
        let line_id = Self::line_id(row);
        match self.line_owned.get(&line_id) {
            Some(false) => return Ok(()),
            Some(true) => {}
            None => {
                if !self.owns(top + row.number(10) / 2.0) {
                    return Ok(());
                }
            }
        }
        if dropped {
            if self.options.explain && !self.options.spans_only && self.text_relevant(&text) {
                let x = round(self.gx + divide((row.number(7) + row.number(9) / 2.0) * self.gw, self.iw)?);
                let y = round(self.gy + divide((top + row.number(10) / 2.0) * self.gh, self.ih)?);
                let reason = if conf.less(&low_floor) {
                    format!("under {}, below even the low floor", int_text(self.options.low_conf))
                } else {
                    format!(
                        "under {} and not a spoken word or piece of one",
                        int_text(self.options.min_conf)
                    )
                };
                self.trace.push(TraceEvent::Drop {
                    conf: conf.text.clone(),
                    text,
                    x: x as i64,
                    y: y as i64,
                    reason,
                });
            }
            return Ok(());
        }
        let key = format!("{}\x1c{line_id}", self.strip_y0.text);
        if key != self.last_key {
            self.flush_line()?;
            self.last_key = key;
        }
        self.line.push(LineWord {
            text,
            low: conf.less(&min_floor),
            conf: conf.text,
            left: row.as_field(7),
            top,
            width: row.as_field(9),
            height: row.as_field(10),
        });
        Ok(())
    }

    /// Whether a word under min_conf may still be the spoken one: it equals a spoken word by look-alike key, or is a
    /// piece of the spoken letters joined.
    fn may_be_spoken(&self, text: &str) -> bool {
        words_of(text).iter().any(|part| {
            let key = compare_key(&normal_word(part));
            (key.len() >= 2 && self.spoken_joined.contains(&key)) || self.spoken_key.contains(&key)
        })
    }

    fn text_relevant(&self, text: &str) -> bool {
        words_of(text)
            .iter()
            .any(|part| self.word_relevant(&compare_key(&normal_word(part))))
    }

    /// Whether a word, as a look-alike key, is a spoken word, one edit from one, a piece of one or of the spoken letters.
    fn word_relevant(&self, key: &str) -> bool {
        for spoken in &self.spoken_key {
            if key == spoken || same_word(key, spoken) {
                return true;
            }
            if spoken.len() >= 4 && key.contains(spoken.as_str()) {
                return true;
            }
        }
        key.len() >= 3 && self.spoken_joined.contains(key)
    }

    /// Splits the finished tesseract line into runs at wide gaps, so a button beside another button is its own run.
    fn flush_line(&mut self) -> Fallible<()> {
        let words = std::mem::take(&mut self.line);
        for (i, word) in words.iter().enumerate() {
            if i > 0 {
                let before = &words[i - 1];
                let gap = word.left.value() - (before.left.value() + before.width.value());
                let taller = if word.height.greater(&before.height) {
                    &word.height
                } else {
                    &before.height
                };
                if gap > taller.value() * 0.8 {
                    self.flush_run()?;
                }
            }
            self.add_token(word);
        }
        self.flush_run()
    }

    /// Splits text into alphanumeric words appended to the run; a token with no alphanumerics is OCR noise and is
    /// dropped. Filler words stay in the run so the matched span can cover them ("sign in").
    fn add_token(&mut self, word: &LineWord) {
        let parts = words_of(&word.text);
        if parts.is_empty() {
            return;
        }
        if !self.run_text.is_empty() {
            self.run_text.push(' ');
        }
        self.run_text.push_str(&word.text);
        for raw in parts {
            let norm = normal_word(&raw);
            self.run.push(RunWord {
                skip: is_filler(&norm),
                low: word.low,
                conf: word.conf.clone(),
                key: compare_key(&norm),
                norm,
                raw,
                left: word.left.clone(),
                top: word.top,
                right: word.left.value() + word.width.value(),
                bottom: word.top + word.height.value(),
            });
        }
    }

    fn hint_of(&self, x: f64, y: f64) -> Fallible<String> {
        let column = divide((x - self.gx) * 3.0, self.gw)?;
        let row = divide((y - self.gy) * 3.0, self.gh)?;
        let column = if column < 1.0 {
            "left"
        } else if column < 2.0 {
            "center"
        } else {
            "right"
        };
        let row = if row < 1.0 {
            "top"
        } else if row < 2.0 {
            "middle"
        } else {
            "bottom"
        };
        Ok(if row == "middle" && column == "center" {
            "middle".to_string()
        } else {
            format!("{row} {column}")
        })
    }

    /// Finds a span of consecutive run words whose letters joined equal the spoken words' letters joined, in either
    /// direction of split. A span that is equal wins over an earlier one that is only close.
    fn joined_span(&mut self, from: usize) -> bool {
        let mut close: Option<(usize, usize)> = None;
        for a in from..self.run.len() {
            let mut joined = String::new();
            let mut has_low = false;
            for b in a..self.run.len() {
                joined.push_str(&self.run[b].norm);
                has_low = has_low || self.run[b].low;
                if joined.len() > self.spoken_joined.len() + 1 {
                    break;
                }
                if b == a && self.spoken_all_n == 1 {
                    continue;
                }
                let key = compare_key(&joined);
                if key == self.spoken_joined {
                    self.span_first = a;
                    self.span_last = b;
                    self.span_exact = true;
                    return true;
                }
                if close.is_none() && !has_low && same_word(&key, &self.spoken_joined) {
                    close = Some((a, b));
                }
            }
        }
        let Some((a, b)) = close else { return false };
        self.span_first = a;
        self.span_last = b;
        self.span_exact = false;
        true
    }

    /// Widens the matched span over filler words directly beside it that the spoken target also holds.
    fn absorb_spoken_fillers(&mut self) {
        let (Some(mut first), Some(mut last)) = (self.first, self.last) else {
            return;
        };
        while first > 0 && self.run[first - 1].skip && self.spoken_filler.contains(&self.run[first - 1].norm) {
            first -= 1;
        }
        while last + 1 < self.run.len()
            && self.run[last + 1].skip
            && self.spoken_filler.contains(&self.run[last + 1].norm)
        {
            last += 1;
        }
        self.first = Some(first);
        self.last = Some(last);
    }

    /// Stores the run words first..last as a candidate with the given match_text: its click point, box and label.
    fn store_candidate(&mut self, match_text: &str, kind: Kind) -> Fallible<()> {
        let (first, last) = (self.first.unwrap_or(0), self.last.unwrap_or(0));
        let mut left: Option<Field> = None;
        let (mut right, mut top, mut bottom): (Option<f64>, Option<f64>, Option<f64>) = (None, None, None);
        for word in &self.run[first..=last] {
            if left
                .as_ref()
                .is_none_or(|left| left.text.is_empty() || word.left.less(left))
            {
                left = Some(word.left.clone());
            }
            if right.is_none_or(|right| word.right > right) {
                right = Some(word.right);
            }
            if top.is_none_or(|top| word.top < top) {
                top = Some(word.top);
            }
            if bottom.is_none_or(|bottom| word.bottom > bottom) {
                bottom = Some(word.bottom);
            }
        }
        let left = left.map_or(0.0, |left| left.value());
        let (right, top, bottom) = (right.unwrap_or(0.0), top.unwrap_or(0.0), bottom.unwrap_or(0.0));
        let x = round(self.gx + divide((left + right) / 2.0 * self.gw, self.iw)?);
        let y = round(self.gy + divide((top + bottom) / 2.0 * self.gh, self.ih)?);
        let found_left = round(self.gx + divide(left * self.gw, self.iw)?);
        let found_top = round(self.gy + divide(top * self.gh, self.ih)?);
        let found_width = round(self.gx + divide(right * self.gw, self.iw)?) - found_left;
        let found_height = round(self.gy + divide(bottom * self.gh, self.ih)?) - found_top;
        let label = if self.run_text.chars().count() > LABEL_LIMIT {
            let kept: String = self.run_text.chars().take(LABEL_KEEP).collect();
            format!("{kept}...")
        } else {
            self.run_text.clone()
        };
        let hint = self.hint_of(x, y)?;
        let (x, y) = (x as i64, y as i64);
        self.found.push(Found {
            candidate: Candidate {
                x,
                y,
                match_text: match_text.to_string(),
                label,
                left: found_left as i64,
                top: found_top as i64,
                width: found_width as i64,
                height: found_height as i64,
            },
            hint,
        });
        if self.options.explain {
            self.trace.push(TraceEvent::Cand {
                run_id: self.run_seq,
                x,
                y,
                kind,
                match_text: match_text.to_string(),
            });
        }
        Ok(())
    }

    /// Stores each stretch of the run whose non-filler words, in order, equal the spoken words by look-alike key.
    fn add_subspans(&mut self) -> Fallible<()> {
        let mut start = 0;
        while start < self.run.len() {
            if self.run[start].skip {
                start += 1;
                continue;
            }
            let mut i = start;
            let mut finish = start;
            let mut matched_all = true;
            for spoken in self.spoken_key.clone() {
                while i < self.run.len() && self.run[i].skip {
                    i += 1;
                }
                if i >= self.run.len() || self.run[i].key != spoken {
                    matched_all = false;
                    break;
                }
                finish = i;
                i += 1;
            }
            if matched_all {
                self.first = Some(start);
                self.last = Some(finish);
                self.absorb_spoken_fillers();
                let spoken_words = self.spoken_words.clone();
                self.store_candidate(&spoken_words, Kind::Span)?;
                start = self.last.unwrap_or(start);
            }
            start += 1;
        }
        Ok(())
    }

    /// Traces the finished run when it holds a relevant word: its words with confidence, and what became of it.
    fn explain_run(&mut self, found_before: usize) {
        if !self.run.iter().any(|word| !word.skip && self.word_relevant(&word.key)) {
            return;
        }
        let words: Vec<String> = self
            .run
            .iter()
            .map(|word| format!("{}({})", word.raw, word.conf))
            .collect();
        let made = self.found.len() - found_before;
        let outcome = if made > 0 {
            format!("{made} candidate{}", if made > 1 { "s" } else { "" })
        } else {
            let missing: Vec<&str> = self
                .spoken_key
                .iter()
                .zip(&self.spoken_raw)
                .filter(|(key, _)| {
                    !self
                        .run
                        .iter()
                        .any(|word| !word.skip && (word.key == **key || (!word.low && same_word(&word.key, key))))
                })
                .map(|(_, raw)| raw.as_str())
                .collect();
            if missing.is_empty() {
                let how = if self.options.spans_only {
                    "the same words in order"
                } else {
                    "one match"
                };
                format!("no candidate: the spoken words are there, but not as {how}")
            } else {
                format!("no candidate: missing {}", missing.join(" "))
            }
        };
        self.trace.push(TraceEvent::Run {
            id: self.run_seq,
            words: words.join(" "),
            outcome,
        });
    }

    /// Matches the spoken words against the finished run and stores a candidate for every occurrence of them, so a run
    /// that says "Settings or Settings" offers both.
    fn flush_run(&mut self) -> Fallible<()> {
        if !self.run.is_empty() {
            self.run_seq += 1;
        }
        let found_before = self.found.len();
        if !self.run.is_empty() && self.options.spans_only {
            self.add_subspans()?;
        } else if !self.run.is_empty() {
            self.used.clear();
            let mut word_hits = 0;
            while self.add_whole_run_candidate(None)? {
                word_hits += 1;
            }
            if word_hits == 0 {
                let mut joined_from = 0;
                while self.add_whole_run_candidate(Some(joined_from))? {
                    joined_from = self.span_last + 1;
                }
            }
        }
        if self.options.explain && !self.run.is_empty() {
            self.explain_run(found_before);
        }
        self.run.clear();
        self.run_text.clear();
        Ok(())
    }

    /// Finds the next occurrence of the spoken words in the run and stores it; false when there is none. Without
    /// `joined_from` it matches word by word, each occurrence taking words not yet used, so occurrences come left to
    /// right. With it, it looks for a joined-letters span from that word on. A failed word-by-word attempt keeps the
    /// words it had used, which the next joined attempt's match_text still reads.
    fn add_whole_run_candidate(&mut self, joined_from: Option<usize>) -> Fallible<bool> {
        self.first = None;
        self.last = None;
        let mut span_used = false;
        let mut picked_raw: HashMap<usize, String> = HashMap::new();
        match joined_from {
            None => {
                for j in 0..self.spoken_n() {
                    let spoken_key = self.spoken_key[j].clone();
                    let mut found = (0..self.run.len())
                        .find(|&i| !self.run[i].skip && !self.used.contains(&i) && self.run[i].key == spoken_key);
                    if let Some(i) = found {
                        picked_raw.insert(i, self.spoken_raw[j].clone());
                    } else {
                        found = (0..self.run.len()).find(|&i| {
                            !self.run[i].skip
                                && !self.run[i].low
                                && !self.used.contains(&i)
                                && same_word(&self.run[i].key, &spoken_key)
                        });
                    }
                    let Some(found) = found else { return Ok(false) };
                    self.used.insert(found);
                    self.first = Some(self.first.map_or(found, |first| first.min(found)));
                    self.last = Some(self.last.map_or(found, |last| last.max(found)));
                }
                self.absorb_spoken_fillers();
            }
            Some(from) => {
                if !self.joined_span(from) {
                    return Ok(false);
                }
                span_used = self.span_exact;
                self.first = Some(self.span_first);
                self.last = Some(self.span_last);
            }
        }
        let (first, last) = (self.first.unwrap_or(0), self.last.unwrap_or(0));
        let mut parts: Vec<String> = Vec::new();
        for (i, word) in self.run.iter().enumerate() {
            if word.low {
                let outside = if span_used {
                    i < first || i > last
                } else {
                    !self.used.contains(&i)
                };
                if outside {
                    continue;
                }
            }
            if span_used && i == self.span_first {
                parts.push(self.spoken_words.clone());
            } else if span_used && i > self.span_first && i <= self.span_last {
                continue;
            } else if !word.skip {
                parts.push(picked_raw.get(&i).cloned().unwrap_or_else(|| word.raw.clone()));
            }
        }
        let kind = if span_used { Kind::Joined } else { Kind::Word };
        self.store_candidate(&parts.join(" "), kind)?;
        Ok(true)
    }

    /// The candidate indexes in reading order: top to bottom, then left to right; ties keep discovery order.
    fn sort_found(&self) -> Vec<usize> {
        let mut order: Vec<usize> = (0..self.found.len()).collect();
        order.sort_by_key(|&i| (self.found[i].candidate.y, self.found[i].candidate.x));
        order
    }
}
