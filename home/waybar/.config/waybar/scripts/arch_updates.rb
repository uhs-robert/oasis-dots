#!/usr/bin/env ruby
# waybar/.config/waybar/scripts/arch_updates.rb
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'
require 'open3'

# ---- knobs (override via env) ----
TTL_MIN   = ENV.fetch('UPDATES_TTL_MIN', '30').to_i
SHOW_ZERO = ENV.fetch('UPDATES_SHOW_ZERO', '0') == '1'

RUNTIME_DIR = ENV.fetch('XDG_RUNTIME_DIR', "/run/user/#{Process.uid}")
CACHE = File.join(RUNTIME_DIR, 'arch_updates.cache.json')

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

# checkupdates (pacman-contrib): exit 0 = updates found, exit 2 = no updates
# Each line: "pkgname oldver -> newver"
def count_pacman_updates
  return nil unless cmd_exists?('checkupdates')

  result = run(['checkupdates'])
  exitcode = result[:status]&.exitstatus

  return nil unless [0, 2].include?(exitcode)

  result[:stdout].lines.count { |l| !l.strip.empty? }
end

# paru -Qua: lists AUR packages with available updates, one per line
# exit 0 regardless of whether updates exist
def count_aur_updates
  return nil unless cmd_exists?('paru')

  result = run(['paru', '-Qua'])
  return nil unless result[:status]&.success?

  result[:stdout].lines.count do |l|
    next false if l.strip.empty?

    pkgname = l.split.first.to_s
    pkgname !~ /-(?:git|svn|hg|bzr|cvs)$/
  end
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
  nil
end

def error_payload
  { 'text' => '', 'class' => 'updates-error' }
end

def build_text_parts(pacman, aur)
  parts = []
  parts << "󰮯 #{pacman}" if pacman.positive?
  parts << "󰏗 #{aur}" if aur.positive?
  parts = ['󰮯 0'] if parts.empty? && SHOW_ZERO
  parts
end

def build_payload(pacman, aur)
  total = pacman + aur
  return { 'text' => '', 'class' => 'updates-0' } if total.zero? && !SHOW_ZERO

  tooltip = "Pacman: #{pacman}\nAUR:    #{aur}"
  {
    'text' => build_text_parts(pacman, aur).join('  '),
    'tooltip' => tooltip,
    'class' => total.positive? ? 'updates-has' : 'updates-0'
  }
end

def fetch_updates
  pacman = count_pacman_updates
  aur    = count_aur_updates

  # If both failed, error out
  return error_payload if pacman.nil? && aur.nil?

  build_payload(pacman || 0, aur || 0)
end

def main
  cached = read_cache
  if cached
    puts JSON.generate(cached)
    return 0
  end

  payload = fetch_updates
  write_cache(payload)
  puts JSON.generate(payload)
  0
end

exit main if __FILE__ == $PROGRAM_NAME
