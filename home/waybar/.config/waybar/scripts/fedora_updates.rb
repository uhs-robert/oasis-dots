#!/usr/bin/env ruby
# waybar/.config/waybar/scripts/fedora_updates.rb
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'
require 'open3'

# ---- knobs (override via env) ----
TTL_MIN = ENV.fetch('UPDATES_TTL_MIN', '30').to_i # refresh cache every N minutes
SHOW_ZERO = ENV.fetch('UPDATES_SHOW_ZERO', '0') == '1' # show "0" instead of hiding

RUNTIME_DIR = ENV.fetch('XDG_RUNTIME_DIR', "/run/user/#{Process.uid}")
CACHE = File.join(RUNTIME_DIR, 'fedora_updates.cache.json')

SKIP_HEADER_RE = /^(?:last metadata|available upgrades)/i.freeze
ROW_RE         = /^\S+(?:\.\S+)?\s+\S+\s+\S+/.freeze # "name[.arch]  version  repo"

def cmd_exists?(command)
  ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
    File.executable?(File.join(path, command))
  end
end

def run(cmd)
  stdout, stderr, status = Open3.capture3(*cmd)
  { stdout: stdout, stderr: stderr, status: status }
rescue StandardError => e
  { stdout: '', stderr: e.message, status: nil }
end

def update_line?(line)
  return false if line.empty?
  return false if line.match?(/last metadata/i)
  return false if line.match?(/available upgrades/i)

  # crude but effective: at least 3 columns separated by spaces
  line.split(/\s+/).length >= 3
end

def count_dnf_updates
  # Prefer dnf5 if available, else dnf
  dnf = cmd_exists?('dnf5') ? 'dnf5' : 'dnf'

  # Fast and parseable: list only upgradable packages
  # -q: quiet; list --upgrades prints table-like lines after the header
  result = run([dnf, '-q', 'list', '--upgrades'])

  # 100 can be "updates available" for some dnf ops
  return nil unless [0, 100].include?(result[:status]&.exitstatus)

  result[:stdout].lines.map(&:strip).count { |line| update_line?(line) }
end

def count_rpm_ostree_updates
  # rpm-ostree upgrade --check returns JSON-ish lines on newer versions
  result = run(['rpm-ostree', 'upgrade', '--check'])

  # 77 may mean no updates in some versions
  return nil unless [0, 77].include?(result[:status]&.exitstatus)

  out = result[:stdout].strip

  # Simple heuristic: count "AvailableUpdate" lines or fallback to "updates:" counts if present
  match = out.match(/AvailableUpdate.*?packages?:\s*(\d+)/im)
  return match[1].to_i if match

  # Fallback: if output contains "No updates available", return 0
  return 0 if out.match?(/no updates/i)

  # As a last resort, say 0 if empty
  out.empty? ? 0 : nil
end

def read_cache
  return nil unless File.exist?(CACHE)

  age = Time.now - File.mtime(CACHE)
  return nil if age > TTL_MIN * 60

  JSON.parse(File.read(CACHE))
rescue StandardError
  nil
end

def write_cache(payload)
  FileUtils.mkdir_p(File.dirname(CACHE))
  tmp = "#{CACHE}.tmp"
  File.write(tmp, "#{JSON.generate(payload)}\n")
  File.rename(tmp, CACHE)
rescue StandardError
  # silently fail
end

def clear_cache
  File.unlink(CACHE) if File.exist?(CACHE)
rescue StandardError
  # silently fail
end

def detect_update_count
  if File.exist?('/run/ostree-booted') && cmd_exists?('rpm-ostree')
    count_rpm_ostree_updates
  else
    count_dnf_updates
  end
end

def error_payload
  { 'text' => '', 'class' => 'updates-error' }
end

def build_payload(count)
  if count.zero? && !SHOW_ZERO
    { 'text' => '', 'class' => 'updates-0' }
  else
    {
      'text' => count.to_s,
      'class' => "updates-#{count.positive? ? 'has' : '0'}"
    }
  end
end

def output_payload(payload)
  puts JSON.generate(payload)
end

def fetch_updates
  count = detect_update_count
  return error_payload if count.nil?

  build_payload(count)
end

def main
  # try cache first
  cached = read_cache
  if cached
    output_payload(cached)
    return 0
  end

  payload = fetch_updates
  write_cache(payload)
  output_payload(payload)
  0
end

exit main if __FILE__ == $PROGRAM_NAME
