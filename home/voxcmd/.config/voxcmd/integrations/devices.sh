# shellcheck shell=bash disable=SC2016
# Hook library of devices.toml: sourced before every hook and action of the integration.

# Each hook prints id<TAB>label<TAB>match_text rows, built from the JSON the helpers below produce. A tab or newline
# in a label would split its row, so both become spaces; an empty match_text means "match the label".
json_to_rows() {
  jq -r '.[] | [(.id | tostring), .label, (.match_text // "")] | map(gsub("[\t\n]"; " ")) | join("\t")'
}

output_candidates() {
  audio_nodes '^Audio/Sink$' Output | labels_containing_words "$VOXCMD_ARG_TARGET" | json_to_rows
}

input_candidates() {
  audio_nodes '^Audio/Source(/Virtual)?$' Input | labels_containing_words "$VOXCMD_ARG_TARGET" | json_to_rows
}

bluetooth_candidates() {
  paired_bluetooth_devices | labels_containing_words "$VOXCMD_ARG_TARGET" | json_to_rows
}

app_candidates() {
  # "set the volume to 20" reaches app_volume_set with the app "the". labels_containing_words offers every device
  # for an articles-only target, which suits "use the microphone" but would put every playing app in a picker here.
  # "make the volume 40" can also skip the optional {set} and land here with "make" as the app, and /usr/bin/make
  # exists, so a set word on its own is never an app. Exit 3 is the hook yield, leaving the phrase to Media and System.
  if names_only_articles "$VOXCMD_ARG_TARGET" || "$VOXCMD_SELF" util intents set | grep -qxF -- "$VOXCMD_ARG_TARGET"; then
    return 3
  fi
  playing_apps | labels_containing_words "$VOXCMD_ARG_TARGET" | or_idle_app "$VOXCMD_ARG_TARGET" | json_to_rows
}

# Voice Help rows are id<TAB>label per output and input. Bluetooth devices are left out: labelling them asks
# bluetoothctl about each one, too slow for opening help.
output_help() {
  audio_nodes '^Audio/Sink$' Output | jq -r '.[] | [(.id | tostring), "Output: \(.label)"] | map(gsub("[\t\n]"; " ")) | join("\t")'
}

input_help() {
  audio_nodes '^Audio/Source(/Virtual)?$' Input | jq -r '.[] | [(.id | tostring), "Input: \(.label)"] | map(gsub("[\t\n]"; " ")) | join("\t")'
}

names_only_articles() {
  [[ " $1 " =~ ^(\ (the|a|an|my))*\ $ ]]
}

# Device labels are long ("Radeon High Definition Audio Controller Digital Stereo (HDMI)"), so voxcmd's fuzzy
# matching finds the scattered letters of "headset" in them. Only devices whose label holds every spoken word are
# offered: a word of four letters or more anywhere in the label, so "speaker" names "Speakers", a shorter one only as
# a whole word, so "it" never names "Digital". Articles are not words here: "use the microphone" arrives as the
# target "the" and should offer every microphone, so with only articles spoken each device's match_text becomes the
# target, which voxcmd's own matching then accepts for all of them.
labels_containing_words() {
  jq -c --arg target "$1" '
    def words: ascii_downcase | [splits("[^a-z0-9]+") | select(. != "")];
    ($target | words | map(select(IN("the", "a", "an", "my") | not))) as $spoken_words
    | if $spoken_words == [] then map(. + {match_text: $target}) else
        map(select((.match_text // .label | ascii_downcase) as $label | ($label | words) as $label_words
          | all($spoken_words[]; . as $word | if ($word | length) >= 4 then $label | contains($word) else IN($label_words[]) end)))
      end'
}

# PipeWire nodes of a media class, labelled by description plus what the device's active route or form factor
# calls it, so "headphones" and "speakers" match even when the description only names the sound card.
# Prints [] when PipeWire is unreachable, since nothing would mean "use the spoken text as the node id".
audio_nodes() {
  local media_class="$1" direction="$2" pipewire_objects
  pipewire_objects=$(pw-dump 2>/dev/null) || pipewire_objects='[]'
  jq -c --arg media_class "$media_class" --arg direction "$direction" '
    {headphone: "Headphones", headset: "Headset", speaker: "Speakers", handset: "Handset", "hands-free": "Hands-free",
     microphone: "Microphone", webcam: "Webcam", tv: "TV", hifi: "Hi-Fi", car: "Car", portable: "Portable"} as $form_factors
    | (map(select(.type == "PipeWire:Interface:Device")) | INDEX(.id | tostring)) as $devices
    | map(select(.type == "PipeWire:Interface:Node" and ((.info.props["media.class"] // "") | test($media_class))))
    | map(.id as $node_id | .info.props as $props
        | ($devices[($props["device.id"] // "" | tostring)] // {}) as $device
        | [($device.info.params.Route // [])[]
            | select(.direction == $direction and .device == $props["card.profile.device"]) | .description]
          + [$form_factors[$props["device.form-factor"] // $device.info.props["device.form-factor"] // ""] // empty]
        | unique as $kinds
        | {id: $node_id, label: (($props["node.description"] // $props["node.name"]) + if $kinds != [] then " (\($kinds | join(", ")))" else "" end)})
  ' <<<"${pipewire_objects:-[]}" 2>/dev/null || echo '[]'
}

# Paired devices, labelled by name plus their kind from the icon BlueZ reports, so "connect my headphones" works.
paired_bluetooth_devices() {
  local line mac device_name icon kind
  while IFS= read -r line; do
    [[ "$line" =~ ^Device\ ([0-9A-F:]{17})\ (.*)$ ]] || continue
    mac="${BASH_REMATCH[1]}" device_name="${BASH_REMATCH[2]}"
    icon=$(timeout 3 bluetoothctl info "$mac" 2>/dev/null | awk '$1 == "Icon:" { print $2 }')
    case "$icon" in
    audio-headset | audio-headphones) kind=Headphones ;;
    audio-card) kind=Speaker ;;
    input-keyboard) kind=Keyboard ;;
    input-mouse) kind=Mouse ;;
    input-gaming) kind=Controller ;;
    phone) kind=Phone ;;
    *) kind="" ;;
    esac
    jq -n -c --arg id "$mac" --arg label "$device_name${kind:+ ($kind)}" '{id: $id, label: $label}'
  done < <(timeout 5 bluetoothctl devices Paired 2>/dev/null) | jq -s -c .
}

# Playback streams grouped by app, so every Firefox tab moves together: the id is the app's stream ids. The label is
# application.name; the binary is matched too, since Electron apps often call themselves Chromium.
playing_apps() {
  local pipewire_objects
  pipewire_objects=$(pw-dump 2>/dev/null) || pipewire_objects='[]'
  jq -c '
    map(select(.type == "PipeWire:Interface:Node" and .info.props["media.class"] == "Stream/Output/Audio")
        | .id as $stream_id | .info.props
        | {id: $stream_id, name: (.["application.name"] // .["application.process.binary"] // .["node.name"] // ""),
           binary: (.["application.process.binary"] // "")}
        | select(.name != ""))
    | group_by(.name | ascii_downcase)
    | map({id: (map(.id | tostring) | join(" ")), label: .[0].name,
           match_text: ([.[0].name] + map(.binary) | map(select(. != "")) | unique_by(ascii_downcase) | join(" "))})
  ' <<<"${pipewire_objects:-[]}" 2>/dev/null || echo '[]'
}

# An app that plays nothing has no stream, so when the name is a running window class or process, or a command on
# PATH, it gets a candidate with the id "idle" (candidate ids cannot be empty) that the actions read as no streams, so
# they report "not playing" rather than the bare "no match". Any other name gets [], which leaves "turn brightness
# down" or "turn the volume up" to the integration they belong to.
or_idle_app() {
  local target="$1" matches app_key
  matches=$(cat)
  app_key=$(tr -cd 'a-z0-9' <<<"${target,,}")
  if [ "$matches" != '[]' ] || [ -z "$app_key" ]; then
    printf '%s\n' "$matches"
  elif type -P "$app_key" >/dev/null || running_app_names | grep -qxF "$app_key"; then
    jq -n -c --arg target "$target" '[{id: "idle", label: "\($target) (not playing)", match_text: $target}]'
  else
    echo '[]'
  fi
}

# Lowercased and alphanumeric only, and a reverse-DNS class reduced to its last part, org.qutebrowser.qutebrowser to
# qutebrowser.
running_app_names() {
  {
    hyprctl clients -j 2>/dev/null | jq -r '.[].class' 2>/dev/null
    ps -eo comm= 2>/dev/null
  } | awk -F. '{ name = tolower($NF); gsub(/[^a-z0-9]/, "", name); if (name != "") print name }'
}

# Steps and levels are percentages of the stream's own volume, clamped to 0..100 so no app is boosted past full.
clamp_percent() {
  local percent=$((10#$1))
  echo $((percent > 100 ? 100 : percent))
}

require_streams() {
  [ -n "$1" ] && return
  echo "$2 is not playing anything; an app has a volume only while it plays"
  return 1
}

# Prints "at 40%" from the first stream; the others moved by the same step or to the same level.
report_app_volume() {
  wpctl get-volume "${1%% *}" | awk '{ printf "at %d%%%s\n", $2 * 100 + 0.5, (/MUTED/ ? " (muted)" : "") }'
}

# -l 1.0 stops a step at 100%; going down, wpctl already stops at 0.
step_app_volume() {
  local stream_ids="${1#idle}" app="$2" direction="$3" step=5 stream
  require_streams "$stream_ids" "$app" || return
  if [[ "${VOXCMD_RAW_TRANSCRIPT,,}" =~ \ by\ ([0-9]+) ]]; then step=$(clamp_percent "${BASH_REMATCH[1]}"); fi
  for stream in $stream_ids; do
    wpctl set-volume -l 1.0 "$stream" "$step%$direction" || return
  done
  report_app_volume "$stream_ids"
}

# The level is the last number spoken, the only one the set verb allows. A replacement can turn the spoken number
# into digits that $VOXCMD_RAW_TRANSCRIPT lacks, and guessing 0 there would silence the app.
set_app_volume() {
  local stream_ids="${1#idle}" app="$2" level stream
  require_streams "$stream_ids" "$app" || return
  level=$(grep -oE '[0-9]+' <<<"$VOXCMD_RAW_TRANSCRIPT" | tail -n 1)
  if [ -z "$level" ]; then
    echo "no level in \"$VOXCMD_RAW_TRANSCRIPT\""
    return 1
  fi
  level=$(clamp_percent "$level")
  for stream in $stream_ids; do
    wpctl set-volume "$stream" "$level%" || return
  done
  report_app_volume "$stream_ids"
}

mute_app() {
  local stream_ids="${1#idle}" app="$2" muted="$3" stream
  require_streams "$stream_ids" "$app" || return
  for stream in $stream_ids; do
    wpctl set-mute "$stream" "$muted" || return
  done
  report_app_volume "$stream_ids"
}
