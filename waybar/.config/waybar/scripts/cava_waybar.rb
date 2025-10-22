#!/usr/bin/env -S ruby --disable=gems
# waybar/.config/waybar/scripts/cava_waybar.rb
# frozen_string_literal: true

# cava_waybar.rb
# waybar/.config/waybar/scripts/cava_waybar.rb
# CAVA → Waybar single-producer + lightweight followers.
# - First instance to grab the lock runs CAVA and writes a shared JSON sink.
# - Other instances just read that file and print it periodically for Waybar.

require 'json'
require 'fileutils'
require 'tempfile'

# ── Env knobs ───────────────────────────────────────────────────────────────
BARS = ENV.fetch('CAVA_BARS', '40').to_i
BIT_FORMAT = ENV.fetch('CAVA_BIT', '16bit') # "8bit" | "16bit"
SENS = ENV.fetch('CAVA_SENS', '150').to_i
CHANNELS = ENV.fetch('CAVA_CHANNELS', 'mono') # "mono" | "stereo"
METHOD = ENV.fetch('CAVA_INPUT', 'pulse')
CLASS_NAME = ENV.fetch('CAVA_CLASS', 'cava')
COLOR_HEX = ENV.fetch('CAVA_COLOR', '#2E2620')

STYLE_NAME = ENV.fetch('CAVA_STYLE', 'blocks') # blocks|braille|dots|tri|shades|ticks|wave
GAP = ENV.fetch('CAVA_GAP', "\u200a") # " ", "│", "·", etc.
BORDER = ENV.fetch('CAVA_BORDER', 'none') # none|pipe|bracket
MARKUP = ENV.fetch('CAVA_MARKUP', '0') == '1' # pango span color

FPS = ENV.fetch('CAVA_FPS', '12').to_i # producer emit cap
FOLLOW_INT = ENV.fetch('CAVA_FOLLOWER_INTERVAL', '1').to_f # follower print period (s)

# Runtime dir for user
RUNTIME_DIR = ENV['XDG_RUNTIME_DIR'] || "/run/user/#{Process.uid}"
SINK_PATH = ENV.fetch('CAVA_SINK', "#{RUNTIME_DIR}/cava_waybar.json")
LOCK_PATH = ENV.fetch('CAVA_LOCK', "#{RUNTIME_DIR}/cava_waybar.lock")

# ── Styles (low→high intensity) ─────────────────────────────────────────────
STYLES = {
  'blocks' => %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █],
  'braille' => %w[⡀ ⡄ ⣆ ⣇ ⣧ ⣷ ⣿],
  'dots' => %w[· • ● ◉],
  'tri' => %w[△ ▲],
  'shades' => %w[░ ▒ ▓ █],
  'ticks' => ['', '|', '||', '|||', '||||', '|||||'],
  'wave' => [' ', '_', '-', '^']
}.freeze

GLYPHS = STYLES.fetch(STYLE_NAME, STYLES['blocks'])

# Bit depth mapping
if BIT_FORMAT == '16bit'
  BYTETYPE = 'S<'
  BYTESIZE = 2
  MAXV = 65_535
else
  BYTETYPE = 'C'
  BYTESIZE = 1
  MAXV = 255
end

# Global stop flag
$stop = false

# Signal handlers
trap('INT') { $stop = true }
trap('TERM') { $stop = true }
begin
  trap('PIPE') { $stop = true }
rescue StandardError
  nil
end

# ── Helper functions ────────────────────────────────────────────────────────

def wrap_token(tok)
  case BORDER
  when 'pipe'
    "│#{tok}│"
  when 'bracket'
    "[#{tok}]"
  else
    tok
  end
end

def val_to_token(val)
  idx = ((val.to_f / MAXV) * (GLYPHS.length - 1)).round
  idx = [[idx, 0].max, GLYPHS.length - 1].min
  GLYPHS[idx]
end

def atomic_write(path, text)
  tmp = "#{path}.tmp"
  File.write(tmp, "#{text}\n")
  File.rename(tmp, path)
end

def try_lock(path)
  FileUtils.mkdir_p(File.dirname(path))
  file = File.open(path, File::CREAT | File::WRONLY, 0o644)

  if file.flock(File::LOCK_EX | File::LOCK_NB)
    file.write(Process.pid.to_s)
    file.flush
    file
  else
    file.close
    nil
  end
rescue Errno::EWOULDBLOCK
  file&.close
  nil
end

# Cache the probe a bit to avoid spamming playerctl
$last_check = 0.0
$last_active = false

def media_active?
  now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  return $last_active if now - $last_check < 0.3

  $last_check = now

  begin
    output = `playerctl -a status 2>/dev/null`
    states = output.lines.map(&:strip).map(&:downcase).reject(&:empty?)
    $last_active = states.any? { |s| %w[playing paused].include?(s) }
  rescue StandardError
    $last_active = false
  end

  $last_active
end

def install_parent_death_sig
  # Linux-specific: ask kernel to send SIGTERM if parent dies
  # This is done via prctl(PR_SET_PDEATHSIG)
  # Ruby doesn't have built-in support, so we use fiddle

  require 'fiddle'
  libc = Fiddle.dlopen('libc.so.6')
  prctl = Fiddle::Function.new(
    libc['prctl'],
    [Fiddle::TYPE_INT, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG],
    Fiddle::TYPE_INT
  )
  pr_set_pdeathsig = 1
  prctl.call(pr_set_pdeathsig, Signal.list['TERM'], 0, 0, 0)
rescue StandardError
  # Not critical, silently ignore
end

def safe_write_line(obj)
  $stdout.puts JSON.generate(obj)
  $stdout.flush
  true
rescue Errno::EPIPE
  false
end

# ── Producer: runs CAVA and writes to sink ─────────────────────────────────

def producer(_lock_file)
  cava_conf = <<~CONF
    [general]
    mode = normal
    framerate = 25
    lower_cutoff_freq = 50
    higher_cutoff_freq = 12000
    bars = #{BARS}
    sensitivity = #{SENS}
    channels = #{CHANNELS}

    [input]
    method = #{METHOD}

    [output]
    method = raw
    raw_target = /dev/stdout
    bit_format = #{BIT_FORMAT}
    channels = #{CHANNELS}
    mono_option = average

    [smoothing]
    noise_reduction = 35
    integral = 90
    gravity = 95
    ignore = 2
    monstercat = 1.5
  CONF

  Tempfile.create(['cava', '.conf']) do |conf|
    conf.write(cava_conf)
    conf.flush

    # Spawn CAVA process
    IO.popen(['cava', '-p', conf.path], 'rb', err: '/dev/null') do |pipe|
      last_emit = 0.0
      chunk_size = BYTESIZE * BARS

      # Initialize sink
      begin
        atomic_write(SINK_PATH, JSON.generate({ text: '', class: CLASS_NAME }))
      rescue StandardError
        nil
      end

      until $stop
        buf = pipe.read(chunk_size)
        break if buf.nil? || buf.bytesize < chunk_size

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        next if now - last_emit < (1.0 / [FPS, 1].max)

        last_emit = now

        # Unpack values based on bit format
        vals = buf.unpack("#{BYTETYPE}#{BARS}")
        tokens = vals.map { |v| val_to_token(v) }
        text = tokens.join(GAP)

        payload = {
          text: media_active? ? text : '',
          class: CLASS_NAME
        }

        begin
          atomic_write(SINK_PATH, JSON.generate(payload))
        rescue StandardError
          nil
        end

        break unless safe_write_line(payload) # Waybar closed pipe
      end

      # Process cleanup handled by IO.popen block exit
    end
  end

  0
end

# ── Follower: reads from sink and prints to Waybar ─────────────────────────

def follower
  last_mtime = 0.0
  last_payload = nil
  sleep_s = [0.002, 0.5 / [FPS, 1].max].max

  # Always print one line immediately
  begin
    last_payload = if File.exist?(SINK_PATH)
                     line = File.read(SINK_PATH).strip
                     line.empty? ? { text: '', class: CLASS_NAME } : JSON.parse(line, symbolize_names: true)
                   else
                     { text: '', class: CLASS_NAME }
                   end
  rescue StandardError
    last_payload = { text: '', class: CLASS_NAME }
  end

  return 0 unless safe_write_line(last_payload)

  until $stop
    begin
      if File.exist?(SINK_PATH)
        st = File.stat(SINK_PATH)
        if st.mtime.to_f != last_mtime
          last_mtime = st.mtime.to_f
          line = File.read(SINK_PATH).strip

          unless line.empty?
            payload = JSON.parse(line, symbolize_names: true)
            if payload != last_payload
              last_payload = payload
              out = media_active? ? payload : { text: '', class: CLASS_NAME }
              break unless safe_write_line(out)
            end
          end
        end
      end
    rescue Errno::ENOENT
      # File doesn't exist yet, ignore
    rescue StandardError
      # Ignore other errors
    end

    sleep sleep_s
  end

  0
end

# ── Main entry point ────────────────────────────────────────────────────────

def main
  install_parent_death_sig

  # Decide role: producer or follower
  lock_file = try_lock(LOCK_PATH)
  if lock_file
    producer(lock_file)
  else
    follower
  end
end

exit(main) if __FILE__ == $PROGRAM_NAME
