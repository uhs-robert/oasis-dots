#!/usr/bin/env ruby
# waybar/.config/waybar/scripts/fake_cava.rb

bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
i = 0

loop do
  s = (0...10).map { |j| bars[(i + j) % bars.length] }.join(" ")
  puts "{\"text\":\"#{s}\"}"
  $stdout.flush
  sleep 0.5
  i = (i + 1) % bars.length
end
