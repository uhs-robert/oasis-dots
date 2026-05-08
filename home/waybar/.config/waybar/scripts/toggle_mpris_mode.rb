#!/usr/bin/env ruby
# waybar/.config/waybar/scripts/toggle_mpris_mode.rb
# frozen_string_literal: true

require 'fileutils'

CONFIG_DIR = File.expand_path(ENV.fetch('XDG_CONFIG_HOME', '~/.config') + '/waybar')
BASE_CONFIG = File.join(CONFIG_DIR, 'config.base.jsonc')
ACTIVE_CONFIG = File.join(CONFIG_DIR, 'config.jsonc')
STATE_FILE = File.join(CONFIG_DIR, '.mpris-mode')

TARGET_OUTPUTS = [
  '"output": "eDP-2"',
  '"output": ["!HP Inc. HP Z22n G2 6CM8411J22", "!eDP-2", "*"]'
].freeze

def read_mode
  mode = File.exist?(STATE_FILE) ? File.read(STATE_FILE, encoding: 'utf-8').strip : 'all'
  %w[all cliamp].include?(mode) ? mode : 'all'
end

def next_mode(mode)
  mode == 'all' ? 'cliamp' : 'all'
end

def replacement_module(mode)
  mode == 'cliamp' ? '"mpris#cliamp"' : '"mpris"'
end

def lines_for(text)
  text.lines
end

def target_block_start?(line)
  TARGET_OUTPUTS.any? { |target| line.include?(target) }
end

def rewrite_modules_left(lines, start_index, mode)
  i = start_index
  modules_left_start = nil

  while i < lines.length
    if i > start_index && lines[i].lstrip.start_with?('// ────────────────────────────────────────────────────────────────────────── //')
      break
    end

    if lines[i].include?('"modules-left"')
      modules_left_start = i
      break
    end
    i += 1
  end

  return unless modules_left_start

  i = modules_left_start
  while i < lines.length
    lines[i] = lines[i].gsub(/"mpris#cliamp"|"mpris"/, replacement_module(mode))
    break if lines[i].include?(']')

    i += 1
  end
end

def build_config(base_text, mode)
  lines = lines_for(base_text)

  lines.each_with_index do |line, index|
    rewrite_modules_left(lines, index, mode) if target_block_start?(line)
  end

  lines.join
end

def restart_waybar
  system('pkill', '-x', 'waybar', exception: false)
  pid = spawn('waybar', out: '/dev/null', err: '/dev/null')
  Process.detach(pid)
end

abort("Base config not found: #{BASE_CONFIG}") unless File.file?(BASE_CONFIG)

current_mode = read_mode
new_mode = next_mode(current_mode)

base_text = File.read(BASE_CONFIG, encoding: 'utf-8')
new_config = build_config(base_text, new_mode)

File.write(ACTIVE_CONFIG, new_config)
File.write(STATE_FILE, "#{new_mode}\n")

restart_waybar

puts "Waybar MPRIS mode: #{new_mode}"
