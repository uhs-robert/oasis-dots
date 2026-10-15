# Mirrors positions() and slot_order() in quickshell/overview/Voice.js, so a monitor has the same words whether the overview
# or `hyprctl monitors -j` is asked; tests/run-monitors.sh runs both on the same layouts and fails when they differ.
# Input: `hyprctl monitors -j`. $slots: the monitor name of each slot in order, space separated, "-" for an empty slot.
# Output: [{id, slot, horizontal, vertical, focused}] in slot order, the shape of overview.json's "monitors". A monitor
# no slot names gets slot 0 (unknown), never a guessed one: the slot order is Hyprland's, and guessing it would send
# "monitor one" to the wrong display.

def words_for($count; $two; $three):
  if $count == 2 then $two
  elif $count == 3 then $three
  elif $count > 3 then [$three[0]] + [range(0; $count - 2) | ""] + [$three[2]]
  else [] end;

# [[index, ...], ...] to [{i, word}]
def cluster_words($list; $two; $three):
  words_for($list | length; $two; $three) as $names
  | [$list | to_entries[] | .key as $k | .value[] | {i: ., word: ($names[$k] // "")}];

# Groups that overlap along x share a cluster; clusters are in order along x.
def x_clusters:
  sort_by([.x, .i])
  | reduce .[] as $g ({out: [], end: 0};
      if (.out | length) == 0 or $g.x >= .end
      then .out += [[$g.i]] | .end = $g.x + $g.w
      else .out[-1] += [$g.i] | .end = ([.end, $g.x + $g.w] | max) end)
  | .out;

# A group joins the row while its top is above every member's bottom, so a tall neighbour sharing the top edge stays in it;
# a group starting at or below the shortest member's bottom starts a new row. Voice.js rows() states the same rule.
def rows:
  sort_by([.y, .h, .i])
  | reduce .[] as $g ({out: [], bottom: null};
      if (.out | length) > 0 and $g.y < .bottom
      then .out[-1] += [$g.i] | .bottom = ([.bottom, $g.y + $g.h] | min)
      else .out += [[$g.i]] | .bottom = $g.y + $g.h end)
  | .out;

[.[] | select(.disabled | not)] as $monitors
| [$monitors | to_entries[]
    | .key as $i | .value
    | (if .scale > 0 then .scale else 1 end) as $scale
    | ((.transform // 0) % 2 == 1) as $turned
    | {i: $i, name, x, y, focused: (.focused // false), id_number: .id,
       w: ((if $turned then .height else .width end) / $scale),
       h: ((if $turned then .width else .height end) / $scale)}] as $groups
| ($groups | rows) as $row_list
| cluster_words($row_list; ["top", "bottom"]; ["top", "middle", "bottom"]) as $vertical
| [$row_list[] as $row
    | [$groups[] | select(.i as $i | $row | index($i))] | x_clusters
    | cluster_words(.; ["left", "right"]; ["left", "middle", "right"])]
  | add // [] | . as $horizontal
| ($slots | split(" ") | map(select(. != ""))) as $named
| [$groups[]
    | . as $g
    | {id: .name,
       slot: (($named | index($g.name)) | if . == null then 0 else . + 1 end),
       horizontal: (($horizontal[] | select(.i == $g.i) | .word) // ""),
       vertical: (($vertical[] | select(.i == $g.i) | .word) // ""),
       focused: .focused}]
| sort_by(if .slot == 0 then 1000 else .slot end)
