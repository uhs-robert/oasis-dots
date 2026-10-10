# shellcheck shell=bash disable=SC2034,SC2016
# Default audio output and input (wpctl) and Bluetooth devices (bluetoothctl). Format: ~/.config/voxcmd/README.md

name="Devices"
confirm=0

# "switch to X" belongs to app switching, so output switching always names the output: "switch audio to X",
# "use X", "output to X". Input verbs come first so "use the X microphone" never reads as an output.
verbs=(
  "bluetooth_on   (turn )?bluetooth on|turn on (the )?bluetooth|enable bluetooth"
  "bluetooth_off  (turn )?bluetooth off|turn off (the )?bluetooth|disable bluetooth"
  # The one target not last: the engine finds its group by counting "(", and the trailing word ends the capture.
  "input          (use|switch to) (the |my )?{target} (microphone|mic)"
  "input          (switch|set|change|use) (the |my )?(microphone|mic|input)( to)? (the |my )?{target}"
  "output         (switch|set|change) (the |my )?(audio|sound|output|speakers?)( output)? to (the |my )?{target}"
  "output         (use|(audio |sound )?output to) (the |my )?{target}"
  "disconnect     disconnect( from)? (the |my )?{target}"
  "connect        (re)?connect( to)? (the |my )?{target}"
)

# set-default moves only the streams following the default (WirePlumber's linking.follow-default-target), never
# one an app pinned to a device. connect powers the adapter on first, so "connect my headphones" works while it is off.
declare -A actions=(
  [bluetooth_on]='bluetoothctl power on'
  [bluetooth_off]='bluetoothctl power off'
  [input]='wpctl set-default "$id"'
  [output]='wpctl set-default "$id"'
  [connect]='bluetoothctl power on >/dev/null && bluetoothctl connect "$id"'
  [disconnect]='bluetoothctl disconnect "$id"'
)

candidates() {
  local action="$1" target="$2"
  case "$action" in
  output) audio_nodes '^Audio/Sink$' Output ;;
  input) audio_nodes '^Audio/Source(/Virtual)?$' Input ;;
  connect | disconnect) paired_bluetooth_devices ;;
  *) return 0 ;;
  esac | labels_containing_words "$target"
}

# Device labels are long ("Radeon High Definition Audio Controller Digital Stereo (HDMI)"), so voxcmd's fuzzy
# matching finds the scattered letters of "headset" in them. Only devices whose label holds every spoken word are
# offered: a word of four letters or more anywhere in the label, so "speaker" names "Speakers", a shorter one only as
# a whole word, so "it" never names "Digital". Articles are not words here: "use the microphone" arrives as the
# target "the" and should offer every microphone.
labels_containing_words() {
  jq -c --arg target "$1" '
    def words: ascii_downcase | [splits("[^a-z0-9]+") | select(. != "")];
    ($target | words | map(select(IN("the", "a", "an", "my") | not))) as $spoken_words
    | map(select((.label | ascii_downcase) as $label | ($label | words) as $label_words
        | all($spoken_words[]; . as $word | if ($word | length) >= 4 then $label | contains($word) else IN($label_words[]) end)))'
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
