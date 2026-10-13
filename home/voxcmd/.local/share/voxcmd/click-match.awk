# Finds the on-screen text a spoken click target names and maps it to global pointer coordinates.
# Run by click.sh over click-ocr's output: CLICK_TARGET="sign in" awk -f click-match.awk (the target comes from the
# environment so backslashes in it are kept as spoken, which -v would turn into escapes)
#
# Input lines:
#   #window <gx> <gy> <gw> <gh> <iw> <ih>   window origin and size in logical coordinates, and the captured image's pixels
#   #strip <i> <y0> <own_top> <own_bottom>  tesseract tsv follows for the strip starting at image row y0, which owns
#                                           the lines whose box centre falls in [own_top, own_bottom)
#   ... tesseract tsv rows
# Output, one candidate per tab-separated line: x, y, match_text, label, then the matched span's bounding box as
# left, top, width, height. All coordinates are integers in global logical coordinates.
#
# match_text is the run's words, with a word that differs from the spoken one only by OCR look-alike letters (compare_key:
# l, I, 1 and | alike, 0 and O alike) replaced by the spoken word, so voxcmd's word matching sees "sign in" for a misread
# "sign ln". A word that is merely one edit away ("Clone" for "close") keeps the OCR text: it is another word as often
# as a misread one, so voxcmd's word matching must call it weak or drop it, never click it.
# A span whose letters joined equal the spoken letters joined under the same look-alike comparison ("Newtask" for
# "new task", "Read me" for "readme") is written as the spoken words, which voxcmd's word matching treats as strong.
# POSIX awk only.

function lowered_alnum(text,   t) {
  t = tolower(text)
  gsub(/'/, "", t)
  return t
}

# Nearest integer, half away from zero: int() alone truncates toward zero, which is wrong below the origin.
function round(v) {
  return v < 0 ? -int(-v + 0.5) : int(v + 0.5)
}

function singular(w) {
  if (length(w) > 3 && w ~ /s$/ && w !~ /ss$/)
    return substr(w, 1, length(w) - 1)
  return w
}

# Same normalisation as voxcmd's word_match: number words to digits, plurals to singular.
function normal_word(raw) {
  if (raw in digit_of)
    return digit_of[raw]
  return singular(raw)
}

# Compares OCR look-alikes (l, I, 1 and | for one letter; 0 and O) as one.
function compare_key(w) {
  if (length(w) < 2)
    return w
  gsub(/[il1]/, "l", w)
  gsub(/0/, "o", w)
  return w
}

function levenshtein_within_one(a, b,   la, lb, i, mismatches) {
  la = length(a)
  lb = length(b)
  if (la < lb) {
    return levenshtein_within_one(b, a)
  }
  if (la - lb > 1)
    return 0
  if (la == lb) {
    for (i = 1; i <= la; i++)
      if (substr(a, i, 1) != substr(b, i, 1) && ++mismatches > 1)
        return 0
    return 1
  }
  for (i = 1; i <= lb; i++)
    if (substr(a, i, 1) != substr(b, i, 1))
      return substr(a, i + 1) == substr(b, i)
  return 1
}

# Noise tolerance grows with the word: short words must match exactly, since one wrong letter is another word.
function same_word(a, b,   la, lb) {
  if (a == b)
    return 1
  la = length(a)
  lb = length(b)
  if (la < 5 || lb < 5)
    return 0
  if (la == 5 || lb == 5)
    return la == lb && levenshtein_within_one(a, b)
  return levenshtein_within_one(a, b)
}

function is_filler(w) {
  return w in filler || w == ""
}

# Splits text into alphanumeric words appended to the run; a token with no alphanumerics ("|", "-") is OCR noise and
# is dropped. Filler words are skipped when matching, as in word_match,
# but stay in the run so the matched span can cover them ("sign in").
function add_token(text, left, top, width, height,   t, parts, n, i, raw) {
  t = lowered_alnum(text)
  gsub(/[^a-z0-9]+/, " ", t)
  n = split(t, parts, " ")
  if (n == 0)
    return
  run_text = run_text (run_text == "" ? "" : " ") text
  for (i = 1; i <= n; i++) {
    raw = parts[i]
    run_n++
    run_skip[run_n] = is_filler(normal_word(raw))
    run_raw[run_n] = raw
    run_key[run_n] = compare_key(normal_word(raw))
    run_norm[run_n] = normal_word(raw)
    run_left[run_n] = left
    run_top[run_n] = top
    run_right[run_n] = left + width
    run_bottom[run_n] = top + height
  }
}

function hint_of(x, y,   column, row) {
  column = (x - gx) * 3 / gw
  row = (y - gy) * 3 / gh
  column = column < 1 ? "left" : (column < 2 ? "center" : "right")
  row = row < 1 ? "top" : (row < 2 ? "middle" : "bottom")
  if (row == "middle" && column == "center")
    return "middle"
  return row " " column
}

# Finds a span of consecutive run words whose letters joined equal the spoken words' letters joined, in either
# direction of split: one OCR word for several spoken words, or several OCR words for one spoken word. Sets
# span_first, span_last and span_exact (equal under look-alike comparison, not merely one edit away); a span that is
# equal wins over an earlier one that is only close. Fillers count here: "sign in" is the letters "signin".
function joined_span(   a, b, joined, close_first, close_last) {
  for (a = 1; a <= run_n; a++) {
    joined = ""
    for (b = a; b <= run_n; b++) {
      joined = joined run_norm[b]
      if (length(joined) > length(spoken_joined) + 1)
        break
      if (b == a && spoken_all_n == 1)
        continue
      if (compare_key(joined) == spoken_joined) {
        span_first = a
        span_last = b
        span_exact = 1
        return 1
      }
      if (close_first == "" && same_word(compare_key(joined), spoken_joined)) {
        close_first = a
        close_last = b
      }
    }
  }
  if (close_first == "")
    return 0
  span_first = close_first
  span_last = close_last
  span_exact = 0
  return 1
}

# Widens the matched span over filler words directly beside it that the spoken target also holds: the click point and
# box belong to "sign in", not to "sign" alone. A filler the speaker did not say is a neighbour, not part of the match.
# Reads and sets the matched span flush_run keeps in first and last.
function absorb_spoken_fillers() {
  while (first > 1 && run_skip[first - 1] && (run_norm[first - 1] in spoken_filler))
    first--
  while (last < run_n && run_skip[last + 1] && (run_norm[last + 1] in spoken_filler))
    last++
}

# Matches the spoken words against the finished run; a hit is stored as a candidate.
function flush_run(   j, i, found, used, text, left, right, top, bottom, x, y, match_text, picked_raw, matched) {
  if (run_n > 0) {
    first = last = ""
    span_used = 0
    delete used
    delete picked_raw
    for (j = 1; j <= spoken_n; j++) {
      found = 0
      for (i = 1; i <= run_n && !found; i++)
        if (!run_skip[i] && !(i in used) && run_key[i] == spoken_key[j]) found = i
      if (found)
        picked_raw[found] = spoken_raw[j]
      for (i = 1; i <= run_n && !found; i++)
        if (!run_skip[i] && !(i in used) && same_word(run_key[i], spoken_key[j])) found = i
      if (!found)
        break
      used[found] = 1
      first = (first == "" || found < first) ? found : first
      last = (last == "" || found > last) ? found : last
    }
    matched = j > spoken_n
    if (!matched && joined_span()) {
      matched = 1
      span_used = span_exact
      first = span_first
      last = span_last
      delete picked_raw
    } else if (matched) {
      absorb_spoken_fillers()
    }
    if (matched) {
      left = right = top = bottom = ""
      match_text = ""
      for (i = 1; i <= run_n; i++) {
        if (i >= first && i <= last) {
          left = (left == "" || run_left[i] < left) ? run_left[i] : left
          right = (right == "" || run_right[i] > right) ? run_right[i] : right
          top = (top == "" || run_top[i] < top) ? run_top[i] : top
          bottom = (bottom == "" || run_bottom[i] > bottom) ? run_bottom[i] : bottom
        }
        if (span_used && i == span_first)
          match_text = match_text (match_text == "" ? "" : " ") spoken_words
        else if (span_used && i > span_first && i <= span_last)
          continue
        else if (!run_skip[i])
          match_text = match_text (match_text == "" ? "" : " ") ((i in picked_raw) ? picked_raw[i] : run_raw[i])
      }
      x = round(gx + (left + right) / 2 * gw / iw)
      y = round(gy + (top + bottom) / 2 * gh / ih)
      found_n++
      found_x[found_n] = x
      found_y[found_n] = y
      found_left[found_n] = round(gx + left * gw / iw)
      found_top[found_n] = round(gy + top * gh / ih)
      found_width[found_n] = round(gx + right * gw / iw) - found_left[found_n]
      found_height[found_n] = round(gy + bottom * gh / ih) - found_top[found_n]
      found_text[found_n] = match_text
      text = run_text
      if (length(text) > 48)
        text = substr(text, 1, 45) "..."
      found_label[found_n] = text
      found_hint[found_n] = hint_of(x, y)
    }
  }
  run_n = 0
  run_text = ""
}

# Splits the finished tesseract line into runs at wide gaps, so a button beside another button is its own run.
function flush_line(   i, gap, limit) {
  for (i = 1; i <= line_n; i++) {
    if (i > 1) {
      gap = line_left[i] - (line_left[i - 1] + line_width[i - 1])
      limit = (line_height[i] > line_height[i - 1] ? line_height[i] : line_height[i - 1]) * 0.8
      if (gap > limit)
        flush_run()
    }
    add_token(line_text[i], line_left[i], line_top[i], line_width[i], line_height[i])
  }
  flush_run()
  line_n = 0
}

# Fills order[] with the candidate indexes in reading order: top to bottom, then left to right.
function sort_found(   i, j, swap) {
  for (i = 1; i <= found_n; i++)
    order[i] = i
  for (i = 2; i <= found_n; i++)
    for (j = i; j > 1 && (found_y[order[j]] < found_y[order[j - 1]] || (found_y[order[j]] == found_y[order[j - 1]] && found_x[order[j]] < found_x[order[j - 1]])); j--) {
      swap = order[j]; order[j] = order[j - 1]; order[j - 1] = swap
    }
}

BEGIN {
  FS = "\t"
  if (min_conf == "")
    min_conf = 60
  split("one two three four five six seven eight nine ten", names, " ")
  for (i = 1; i <= 10; i++)
    digit_of[names[i]] = i
  split("the a an my this that please to of on in for it", fillers, " ")
  for (i in fillers)
    filler[fillers[i]] = 1

  target = ENVIRON["CLICK_TARGET"]
  t = lowered_alnum(target)
  gsub(/[^a-z0-9]+/, " ", t)
  n = split(t, parts, " ")
  for (i = 1; i <= n; i++) {
    spoken_all_n++
    spoken_words = spoken_words (spoken_words == "" ? "" : " ") parts[i]
    spoken_joined = spoken_joined normal_word(parts[i])
    if (is_filler(normal_word(parts[i]))) {
      spoken_filler[normal_word(parts[i])] = 1
      continue
    }
    spoken_n++
    spoken_raw[spoken_n] = parts[i]
    spoken_key[spoken_n] = compare_key(normal_word(parts[i]))
  }
  if (spoken_n == 0)
    exit
  spoken_joined = compare_key(spoken_joined)
}

/^#window / {
  split($0, w, " ")
  gx = w[2]; gy = w[3]; gw = w[4]; gh = w[5]; iw = w[6]; ih = w[7]
  next
}

/^#strip / {
  flush_line()
  split($0, w, " ")
  strip_y0 = w[3]; own_top = w[4]; own_bottom = w[5]
  last_key = ""
  delete line_owned
  next
}

# A line box (level 4) decides for all its words which strip owns them, by the box's centre. Per word, a line crossing
# a cut would be split between two strips and neither would hold the whole run.
$1 == 4 {
  centre = $8 + strip_y0 + $10 / 2
  line_owned[$3 SUBSEP $4 SUBSEP $5] = (centre >= own_top && centre < own_bottom)
  next
}

# Word rows only (level 5), and only confident, non-blank ones.
$1 == 5 {
  text = $12
  gsub(/^[ ]+|[ ]+$/, "", text)
  if (text == "" || $11 < min_conf)
    next
  top = $8 + strip_y0
  line_id = $3 SUBSEP $4 SUBSEP $5
  # Without a line row, as in hand-made input, the word's own centre decides.
  if (line_id in line_owned) {
    if (!line_owned[line_id])
      next
  } else {
    centre = top + $10 / 2
    if (centre < own_top || centre >= own_bottom)
      next
  }
  key = strip_y0 SUBSEP line_id
  if (key != last_key) {
    flush_line()
    last_key = key
  }
  line_n++
  line_text[line_n] = text
  line_left[line_n] = $7
  line_top[line_n] = top
  line_width[line_n] = $9
  line_height[line_n] = $10
}

END {
  if (spoken_n == 0)
    exit
  flush_line()
  sort_found()
  for (k = 1; k <= found_n; k++) {
    i = order[k]
    label = found_label[i] " - " found_hint[i]
    total = 0
    for (j = 1; j <= found_n; j++)
      if (found_label[j] " - " found_hint[j] == label)
        total++
    seen[label]++
    if (total > 1)
      label = label " #" seen[label]
    printf "%d\t%d\t%s\t%s\t%d\t%d\t%d\t%d\n", found_x[i], found_y[i], found_text[i], label, found_left[i], found_top[i], found_width[i], found_height[i]
  }
}
