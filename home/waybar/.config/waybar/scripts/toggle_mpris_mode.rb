#!/usr/bin/env ruby
# waybar/.config/waybar/scripts/toggle_mpris_mode.rb
# frozen_string_literal: true

CONFIG = File.expand_path('~/.config/waybar/config.jsonc')

def restart_waybar
  system('pkill', '-x', 'waybar', exception: false)
  pid = spawn('waybar', out: '/dev/null', err: '/dev/null')
  Process.detach(pid)
end

abort("Config not found: #{CONFIG}") unless File.file?(CONFIG)

text = File.read(CONFIG, encoding: 'utf-8')

if text.match?(/^\s+"mpris",/)
  # Switch to cliamp: comment "mpris", uncomment "mpris#cliamp"
  text.gsub!(/^(\s+)"mpris",\n/) { "#{Regexp.last_match(1)}// \"mpris\",\n" }
  text.gsub!(%r{^(\s+)// "mpris#cliamp",\n}) { "#{Regexp.last_match(1)}\"mpris#cliamp\",\n" }
  new_mode = 'cliamp'
else
  # Switch to all: uncomment "mpris", comment "mpris#cliamp"
  text.gsub!(/^(\s+)"mpris#cliamp",\n/)   { "#{Regexp.last_match(1)}// \"mpris#cliamp\",\n" }
  text.gsub!(%r{^(\s+)// "mpris",\n})     { "#{Regexp.last_match(1)}\"mpris\",\n" }
  new_mode = 'all'
end

File.write(CONFIG, text)
restart_waybar

puts "Waybar MPRIS mode: #{new_mode}"
