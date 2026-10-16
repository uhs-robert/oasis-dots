# Finds the verbs whose words are all in a phrase, in any order, though the phrase does not match their pattern.
# Run by voxcmd's near_miss_options with the normalized phrase in the environment (NEAR_MISS_PHRASE) over lines of
# "<action><TAB><pattern>", the patterns being a verb's ERE with its intents already expanded and {target} and {number}
# still in place. Prints "<action><TAB><target><TAB><has_target><TAB><leftover>" per verb that is a near miss, its best
# reading only. The rules are in the README ("Near misses").
#
# A pattern is read into slots, each a list of alternatives, each alternative a list of words that must all be present:
#   - a literal word is a slot of one alternative; {number} is a slot that a digit word fills
#   - a group with alternatives, "(move|send|bring up)", is one slot; a group followed by "?" is dropped
#   - a slot whose alternatives are all filler words ("the", "to"), or that has an empty alternative, is dropped
#   - in an alternative with a non-filler word, filler words are dropped too ("go to" needs "go")
#   - a nested group inside an alternative is dropped when optional or filler-only; any other kind makes the verb
#     unreadable, as do character classes, anchors, "." and "*" and "+" (or "?" after a single character), escapes, a
#     group glued to a word ("(un)mute"), and {target} anywhere but top level
# The words left over must be none (no {target}) or one run of non-filler speech that becomes the target.
# A verb with no slot left, or unreadable, is skipped: guessing would let any phrase through.
# Top-level alternatives ("a b|c d") are separate readings of the verb.

function is_filler(word) { return word in filler }

function fail() { bad = 1 }

# Reads a sequence up to the closing ")" or "|" (or the end) at the current depth and returns its slots joined by RS_SLOT.
function parse_seq(depth,    out, word, c, group, glued, next_char, unreadable) {
  out = ""
  word = ""
  while (pos <= length(pattern) && !bad) {
    c = substr(pattern, pos, 1)
    if (c == ")" || c == "|") break
    if (c == " ") {
      out = add_word(out, word)
      word = ""
      pos++
    } else if (c ~ /[a-z0-9\x27]/) {
      word = word c
      pos++
      if (substr(pattern, pos, 1) == "?") fail()
    } else if (c == "{") {
      if (word != "") fail()
      if (index(substr(pattern, pos), "{target}") == 1) {
        if (depth > 0 || has_target) fail()
        has_target = 1
      } else if (index(substr(pattern, pos), "{number}") == 1) {
        out = add_word(out, "#number")
      } else fail()
      pos += 8
      next_char = substr(pattern, pos, 1)
      if (next_char != "" && next_char !~ /[ )|]/) fail()
    } else if (c == "(") {
      glued = word != ""
      pos++
      group = parse_group(depth + 1)
      unreadable = group_unreadable
      if (substr(pattern, pos, 1) != ")") fail()
      pos++
      next_char = substr(pattern, pos, 1)
      if (next_char == "?") {
        pos++
        group = ""
      } else if (unreadable) fail()
      else if (next_char == "*" || next_char == "+") fail()
      else if (glued || (next_char != "" && next_char !~ /[ )|]/ && !(next_char == "(" && substr(pattern, pos + 1, 1) == " "))) fail()
      if (group != "") out = out (out == "" ? "" : RS_SLOT) group
    } else fail()
  }
  return add_word(out, word)
}

function add_word(out, word) {
  if (word == "") return out
  return out (out == "" ? "" : RS_SLOT) word
}

# Reads the alternatives of a group, after its "(", and returns them joined by RS_ALT as the group's slot, or "" when the
# group does not constrain the phrase (an empty alternative, or only filler words). Leaves pos on the closing ")".
function parse_group(depth,    alts, flat, words, count, i, kept, optional, all_filler, unreadable) {
  alts = ""
  unreadable = 0
  optional = 0
  all_filler = 1
  while (!bad) {
    flat = flatten(parse_seq(depth))
    if (flat_unreadable) unreadable = 1
    count = split(flat, words, " ")
    kept = ""
    for (i = 1; i <= count; i++) if (!is_filler(words[i])) kept = kept (kept == "" ? "" : " ") words[i]
    if (count == 0) optional = 1
    # Filler goes from an alternative with other words ("go to" needs "go"), but "to" alone stays an alternative.
    if (kept != "") { all_filler = 0; flat = kept }
    if (count > 0) alts = alts (alts == "" ? "" : RS_ALT) flat
    if (substr(pattern, pos, 1) != "|") break
    pos++
  }
  group_unreadable = unreadable
  if (bad || optional || all_filler) return ""
  return alts
}

# An alternative's slots as one word list. A slot with alternatives of its own inside an alternative cannot be kept apart
# from the rest, so the group is unreadable: harmless when it is optional, the verb's end when required.
function flatten(slots,    n, parts, i, out) {
  flat_unreadable = 0
  if (slots == "") return ""
  n = split(slots, parts, RS_SLOT)
  out = ""
  for (i = 1; i <= n; i++) {
    if (index(parts[i], RS_ALT) > 0) { flat_unreadable = 1; return "" }
    out = out (out == "" ? "" : " ") parts[i]
  }
  return out
}

# The top-level slots without the literal filler words, which the phrase may or may not say.
function drop_filler(slots,    n, parts, i, out) {
  if (slots == "") return ""
  n = split(slots, parts, RS_SLOT)
  out = ""
  for (i = 1; i <= n; i++) if (!is_filler(parts[i])) out = out (out == "" ? "" : RS_SLOT) parts[i]
  return out
}

# Fills one slot's alternatives, then goes on to the next slot; backtracks over which phrase words the slots take.
function solve(slot_index,    n, alts, a) {
  if (slot_index > slot_count) return finish()
  n = split(slot_alts[slot_index], alts, RS_ALT)
  for (a = 1; a <= n; a++) if (place(slot_index, alts[a], 1)) return 1
  return 0
}

function place(slot_index, alt, k,    count, words, p) {
  count = split(alt, words, " ")
  if (k > count) return solve(slot_index + 1)
  for (p = 1; p <= phrase_count; p++) {
    if (used[p]) continue
    if (words[k] == "#number" ? phrase[p] ~ /^[0-9]+$/ : phrase[p] == words[k]) {
      used[p] = 1
      if (place(slot_index, alt, k + 1)) return 1
      used[p] = 0
    }
  }
  return 0
}

# All slots are filled: the words left over must fit the verb. With {target} a non-filler one becomes the target, else
# none may remain, so stray speech stays a miss.
function finish(    p, nonfiller, first, last, text, count) {
  nonfiller = 0
  count = 0
  first = 0
  last = 0
  for (p = 1; p <= phrase_count; p++) {
    if (used[p]) continue
    count++
    if (!is_filler(phrase[p])) {
      nonfiller++
      if (!first) first = p
      last = p
    }
  }
  if (has_target ? nonfiller == 0 : nonfiller > 0) return 0
  # The target is one run of speech: a slot's word between two target words ("double click it") splits it in two.
  if (has_target) for (p = first; p <= last; p++) if (used[p]) return 0
  text = ""
  if (has_target) for (p = first; p <= last; p++) if (!used[p]) text = text (text == "" ? "" : " ") phrase[p]
  result_target = text
  result_leftover = count
  return 1
}

function try_reading(    p, n, i) {
  for (p = 1; p <= phrase_count; p++) used[p] = 0
  slot_count = split(reading_slots, slot_alts, RS_SLOT)
  if (reading_slots == "") slot_count = 0
  if (slot_count == 0) return 0
  return solve(1)
}

BEGIN {
  FS = "\t"
  RS_SLOT = "\034"
  RS_ALT = "\035"
  split("the a an this that my please to of on over", filler_words, " ")
  for (i in filler_words) filler[filler_words[i]] = 1
  phrase_count = split(ENVIRON["NEAR_MISS_PHRASE"], phrase, " ")
  # A long phrase is dictation, not a command with its words in the wrong order.
  if (phrase_count > 16) exit
}

{
  action = $1
  pattern = $2
  pos = 1
  best = -1
  while (pos <= length(pattern)) {
    bad = 0
    has_target = 0
    reading_slots = drop_filler(parse_seq(0))
    if (!bad && pos <= length(pattern) && substr(pattern, pos, 1) != "|") fail()
    pos++
    if (bad) {
      # One unreadable reading drops the whole verb, readings that filled before it included.
      best = -1
      break
    }
    if (try_reading() && (best < 0 || result_leftover < best)) {
      best = result_leftover
      best_target = result_target
      best_has_target = has_target
    }
  }
  if (best >= 0) printf "%s\t%s\t%s\t%s\n", action, best_target, best_has_target ? "true" : "false", best
}
