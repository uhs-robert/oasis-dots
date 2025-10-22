#!/usr/bin/env ruby
# waybar/.config/waybar/scripts/weather-api/get_weather.rb
# frozen_string_literal: true

# Waybar weather (WeatherAPI.com)
# - Text: current temp + icon (colored via <span>)
# - Tooltip: current details + next N hours table + up to 7-day table
# - Uses your weather_icons.json mapping for the condition glyph
# - Emits Waybar JSON (set return-type=json, markup=true)
#
# Config file (same dir): weather_settings.json
# {
#   "key": "YOUR_WEATHERAPI_KEY",
#   "parameters": "40.71,-74.01",      // "lat,lon" or "City"
#   "unit": "Fahrenheit",               // or "Celsius"
#   "icon-position": "left",            // or "right"
#   "hours_ahead": 6                    // # of hourly rows to show
# }

require 'json'
require 'set'
require 'net/http'
require 'uri'
require 'time'
require 'cgi'
require 'fileutils'

# ─── Constants ──────────────────────────────────────────────────────────────
COLOR_PRIMARY = '#42A5F5'
ICON_SIZE = '14000' # pango units; ~14pt
ICON_SIZE_LG = '18000'
ICON_SIZE_SM = '12000'
SEASONAL_BIAS = ENV.fetch('SEASONAL_BIAS', '1') == '1'

POP_ALERT_THRESHOLD = 60
POP_ICON_HIGH = ''
POP_ICON_LOW  = ''
SUNRISE_ICON  = ''
SUNSET_ICON   = '󰖚'

THERMO_COLD    = ''
THERMO_NEUTRAL = ''
THERMO_WARM    = ''
THERMO_HOT     = ''

COLOR_COLD = 'skyblue'
COLOR_NEUTRAL = COLOR_PRIMARY
COLOR_WARM = 'khaki'
COLOR_HOT = 'indianred'

COLOR_POP_LOW = '#EAD7FF'
COLOR_POP_MED = '#CFA7FF'
COLOR_POP_HIGH = '#BC85FF'
COLOR_POP_VHIGH = '#A855F7'
COLOR_DIVIDER = '#2B3B57'

DIVIDER_CHAR = '─'
DIVIDER_LEN = 74

HOUR_TABLE_HEADER_TEXT = format('%-4s │ %5s │ %4s │ %7s │ Cond', 'Hr', 'Temp', 'PoP', 'Precip')
DAY_TABLE_HEADER_TEXT = format('%-9s │ %5s │ %5s │ %4s │ %7s │ Cond', 'Day', 'Hi', 'Lo', 'PoP', 'Precip')
DETAIL3H_HEADER_TEXT = format('%-9s │ %2s │ %5s │ %4s │ %7s │ Cond', 'Date', 'Hr', 'Temp', 'PoP', 'Precip')
ASTRO3D_HEADER_TEXT = format('%-9s │ %5s │ %5s', 'Date', 'Rise', 'Set')

# ─── Utilities ──────────────────────────────────────────────────────────────
def safe(hash, key, default = nil)
  hash.key?(key) ? hash[key] : default
end

def load_json(path)
  JSON.parse(File.read(path, encoding: 'utf-8'))
end

def divider(length = DIVIDER_LEN, char = DIVIDER_CHAR, color = COLOR_DIVIDER)
  line = char * [1, length].max
  "<span font_family='monospace' foreground='#{color}'>#{line}</span>"
end

def to_int(val, default = 0)
  Integer(val, exception: false) ||
    Float(val, exception: false)&.to_i ||
    default
end

def to_float(val, default = 0.0)
  Float(val, exception: false) || default
end

def fmt_hour(datetime)
  datetime.strftime('%H')
end

def fmt_day_of_week(datestr)
  # e.g., 'Mon 10/06'
  Time.strptime(datestr, '%Y-%m-%d').strftime('%a %m/%d')
end

def seasonal_cold_limit_c(month = Time.now.month)
  return 10 if (5..9).cover?(month)
  return 8 if [3, 4, 10].include?(month)

  5
end

def seasonal_cold_limit_f(month = Time.now.month)
  ((seasonal_cold_limit_c(month) * 9.0 / 5.0) + 32).round
end

def thermo_bands(unit)
  if celsius_unit?(unit)
    cold = SEASONAL_BIAS ? seasonal_cold_limit_c : 5
    [
      [cold, THERMO_COLD,    COLOR_COLD],
      [20,  THERMO_NEUTRAL,  COLOR_NEUTRAL],
      [28,  THERMO_WARM,     COLOR_WARM],
      [Float::INFINITY, THERMO_HOT, COLOR_HOT]
    ]
  else
    cold = SEASONAL_BIAS ? seasonal_cold_limit_f : 41
    [
      [cold, THERMO_COLD,    COLOR_COLD],
      [68,  THERMO_NEUTRAL,  COLOR_NEUTRAL],
      [82,  THERMO_WARM,     COLOR_WARM],
      [Float::INFINITY, THERMO_HOT, COLOR_HOT]
    ]
  end
end

def fmt_astro_24h(time_str)
  # WeatherAPI astro times come as '07:01 AM' local. Return '07:01' (24h).
  Time.strptime(time_str.strip, '%I:%M %p').strftime('%H:%M')
rescue ArgumentError
  time_str.strip
end

def get_sun_times(blob, now_local)
  # Find today's sunrise/sunset from forecastday[].astro.
  fc = safe(safe(blob, 'forecast', {}), 'forecastday', [])
  today = now_local.strftime('%Y-%m-%d')
  fc.each do |d|
    next unless safe(d, 'date', '').to_s == today

    astro = safe(d, 'astro', {})
    sr = fmt_astro_24h(safe(astro, 'sunrise', '').to_s)
    ss = fmt_astro_24h(safe(astro, 'sunset', '').to_s)
    return [sr, ss]
  end
  ['', '']
end

def icon_for_pop(pop)
  pop >= POP_ALERT_THRESHOLD ? POP_ICON_HIGH : POP_ICON_LOW
end

def celsius_unit?(unit)
  unit.to_s.strip.start_with?('°C')
end

def thermometer_for_temp(temp, unit)
  bands = thermo_bands(unit)
  _, glyph, color = bands.find { |limit, _, _| temp < limit }
  [glyph, color]
end

def color_for_temp(val, unit)
  thermometer_for_temp(val, unit)[1]
end

def pop_color(pop)
  pop = [[0, pop.to_i].max, 100].min
  return COLOR_POP_LOW if pop < 30    # 0–29
  return COLOR_POP_MED if pop < 60    # 30–59
  return COLOR_POP_HIGH if pop < 80   # 60–79

  COLOR_POP_VHIGH # 80–100
end

def mode_file
  state_home = ENV['XDG_STATE_HOME'] || File.expand_path('~/.local/state')
  dir = File.join(state_home, 'waybar')
  FileUtils.mkdir_p(dir)
  File.join(dir, 'weather_mode')
end

def get_mode
  mode = File.read(mode_file, encoding: 'utf-8').strip
  %w[default weekview].include?(mode) ? mode : 'default'
rescue Errno::ENOENT
  'default'
end

def set_mode(mode)
  File.write(mode_file, mode, encoding: 'utf-8')
end

def cycle_mode(direction = 'next')
  modes = %w[default weekview]
  cur = get_mode
  i = modes.index(cur) || 0
  i = direction == 'prev' ? (i - 1) % modes.length : (i + 1) % modes.length
  set_mode(modes[i])
end

def build_astro_by_date(blob)
  # Map 'YYYY-MM-DD' -> [sunrise_24h, sunset_24h] for all forecast days.
  out = {}
  safe(safe(blob, 'forecast', {}), 'forecastday', []).each do |d|
    date_str = safe(d, 'date', '').to_s
    astro = safe(d, 'astro', {})
    sr = fmt_astro_24h(safe(astro, 'sunrise', '').to_s)
    ss = fmt_astro_24h(safe(astro, 'sunset', '').to_s)
    out[date_str] = [sr, ss]
  end
  out
end

def make_astro3d_table(rows, astro_by_date)
  # Build a compact table for sunrise/sunset for the dates present in rows.
  header = "<span weight='bold'>#{ASTRO3D_HEADER_TEXT}</span>"
  dates = rows.map { |r| r['date'].to_s }.uniq.sort
  lines = dates.map do |date|
    sr, ss = astro_by_date.fetch(date, ['', ''])
    sr = (sr.empty? ? '—' : sr)[0, 5]
    ss = (ss.empty? ? '—' : ss)[0, 5]
    format('%-9s │ %5s │ %5s', fmt_day_of_week(date), sr, ss)
  end

  return 'No sunrise/sunset data' if lines.empty?

  "<span font_family='monospace'>#{header}\n#{lines.join("\n")}</span>"
end

# ─── Icons ──────────────────────────────────────────────────────────────────
def load_icon_map(script_path)
  data = load_json(File.join(script_path, 'weather_icons.json'))
  data.is_a?(Array) ? data : []
rescue StandardError
  []
end

def norm(str)
  str.to_s.strip.downcase
end

def to_set(val)
  return Set.new if val.nil?
  return Set.new(val.map { |x| norm(x) }) if val.is_a?(Array)

  Set[norm(val)]
end

def map_condition_icon(icon_map, text, is_day)
  t = norm(text)

  # exact day/night bucket match
  icon_map.each do |item|
    day_set = to_set(item['day'])
    night_set = to_set(item['night'])
    return item['icon'] || '' if is_day && day_set.include?(t)
    return item['icon-night'] || '' if !is_day && night_set.include?(t)
  end

  # fallback: any match regardless of bucket
  icon_map.each do |item|
    if [norm(item['day']), norm(item['night'])].include?(t)
      return is_day ? (item['icon'] || '') : (item['icon-night'] || '')
    end
  end

  # final synonym fallback
  if t == 'clear' && !is_day
    icon_map.each do |item|
      return item['icon-night'] || item['icon'] || '' if norm(item['day']) == 'sunny'
    end
  elsif t == 'sunny' && is_day
    icon_map.each do |item|
      return item['icon'] || '' if norm(item['day']) == 'sunny'
    end
  end

  ''
end

def style_icon(glyph, color = COLOR_PRIMARY, size = ICON_SIZE)
  "<span foreground='#{color}' size='#{size}'>#{glyph} </span>"
end

# ─── Data fetch / parse ─────────────────────────────────────────────────────
def load_config(script_path)
  cfg_path = File.join(script_path, 'weather_settings.json')
  data = load_json(cfg_path)
  raise 'weather_settings.json must be a JSON object' unless data.is_a?(Hash)

  data
end

def fetch_weatherapi_forecast(key, query)
  url = URI('http://api.weatherapi.com/v1/forecast.json')
  params = { key: key, q: query, days: 7, aqi: 'no', alerts: 'no' }
  url.query = URI.encode_www_form(params)

  response = Net::HTTP.get_response(url)
  raise "HTTP Error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  data = JSON.parse(response.body)
  raise 'Unexpected response from WeatherAPI' unless data.is_a?(Hash)

  data
end

def extract_current(blob, unit_c)
  loc = blob['location']
  cur = blob['current']
  cond = cur['condition']['text'].to_s
  temp = to_float(unit_c ? cur['temp_c'] : cur['temp_f'])
  feels = to_float(unit_c ? cur['feelslike_c'] : cur['feelslike_f'])
  precip_amt = to_float(unit_c ? cur['precip_mm'] : cur['precip_in'])
  is_day = to_int(cur['is_day'], 1) == 1 ? 1 : 0
  # naive local time (matches our hourly timestamps below)
  now_local = Time.strptime(loc['localtime'].to_s, '%Y-%m-%d %H:%M')

  {
    'loc' => loc,
    'cond' => cond,
    'temp' => temp,
    'feels' => feels,
    'precip_amt' => precip_amt,
    'is_day' => is_day,
    'now_local' => now_local
  }
end

def build_next_hours(blob, unit_c, now_local, limit)
  fc = blob['forecast']['forecastday']
  hours_list = []

  fc[0..1].each do |d| # up to ~48 hours
    d['hour'].each do |h|
      dt = Time.at(to_int(h['time_epoch']))
      hours_list << {
        'dt' => dt,
        'pop' => to_int(h['chance_of_rain']),
        'precip' => to_float(unit_c ? h['precip_mm'] : h['precip_in']),
        'temp' => to_float(unit_c ? h['temp_c'] : h['temp_f']),
        'cond' => h['condition']['text'].to_s,
        'is_day' => to_int(h['is_day'], 1) == 1 ? 1 : 0
      }
    end
  end

  next_hours = hours_list.select { |h| h['dt'] >= now_local }[0, [0, limit].max]
  next_hours = hours_list[0, [0, limit].max] if next_hours.empty? && !hours_list.empty?
  next_hours
end

def build_next_days(blob, unit_c, max_days = 7)
  fc = blob['forecast']['forecastday']
  days = []

  fc[0...max_days].each do |d|
    day = d['day']
    days << {
      'date' => d['date'].to_s,
      'pop' => to_int(day['daily_chance_of_rain']),
      'max' => to_float(unit_c ? day['maxtemp_c'] : day['maxtemp_f']),
      'min' => to_float(unit_c ? day['mintemp_c'] : day['mintemp_f']),
      'cond' => day['condition']['text'].to_s,
      'precip' => to_float(unit_c ? day['totalprecip_mm'] : day['totalprecip_in'])
    }
  end

  days
end

def build_next_3days_detailed(blob, unit_c, now_local, num_days = 3)
  fc = blob['forecast']['forecastday']
  today = now_local.strftime('%Y-%m-%d')

  rows = []
  picked = 0

  fc.each do |d|
    date_str = d['date'].to_s
    next if date_str <= today # skip today and any past

    picked += 1
    d['hour'].each do |h|
      dt = Time.at(to_int(h['time_epoch']))
      next unless (dt.hour % 3).zero? # downsample to 3h grid

      rows << {
        'date' => date_str,
        'dt' => dt,
        'temp' => to_float(unit_c ? h['temp_c'] : h['temp_f']),
        'pop' => to_int(h['chance_of_rain']),
        'precip' => to_float(unit_c ? h['precip_mm'] : h['precip_in']),
        'cond' => h['condition']['text'].to_s,
        'is_day' => to_int(h['is_day'], 1) == 1 ? 1 : 0
      }
    end

    break if picked >= num_days
  end

  # stable ordering: by date, then time
  rows.sort_by { |r| [r['date'], r['dt']] }
end

# ─── Tables & Tooltip ───────────────────────────────────────────────────────
def make_hour_table(next_hours, unit, precip_unit, icon_map)
  header = "<span weight='bold'>#{HOUR_TABLE_HEADER_TEXT}</span>"
  rows = []

  next_hours.each do |h|
    temp_txt = "#{h['temp'].round}#{unit}".rjust(5)
    temp_col = "<span foreground='#{color_for_temp(h['temp'], unit)}'>#{temp_txt}</span>"

    pop_txt = "#{h['pop'].to_i}%".rjust(4)
    pop_col = "<span foreground='#{pop_color(h['pop'])}'>#{pop_txt}</span>"

    precip_col = format('%<val>.1f %<unit>s', val: h['precip'], unit: precip_unit).rjust(7)

    glyph = map_condition_icon(icon_map, h['cond'].to_s, h['is_day'] != 0)
    icon_html = glyph.empty? ? '' : style_icon(glyph, COLOR_PRIMARY, ICON_SIZE_SM)
    cond_cell = "#{icon_html} #{CGI.escapeHTML(h['cond'].to_s)}".strip

    rows << format('%-4s │ %s │ %s │ %s │ %s',
                   fmt_hour(h['dt']), temp_col, pop_col, precip_col, cond_cell)
  end

  return 'No hourly data' if rows.empty?

  "<span font_family='monospace'>#{header}\n#{rows.join("\n")}</span>"
end

def make_day_table(days, unit, precip_unit, icon_map)
  header = "<span weight='bold'>#{DAY_TABLE_HEADER_TEXT}</span>"
  out_rows = []

  days.each do |d|
    hi_val = d['max'].round
    lo_val = d['min'].round

    hi_txt = format('%3d%s', hi_val, unit)
    lo_txt = format('%3d%s', lo_val, unit)

    hi_col = "<span foreground='#{color_for_temp(d['max'], unit)}'>#{hi_txt}</span>"
    lo_col = "<span foreground='#{color_for_temp(d['min'], unit)}'>#{lo_txt}</span>"

    pop = [[0, d['pop'].to_i].max, 100].min
    pop_txt = format('%3d%%', pop)
    pop_col = "<span foreground='#{pop_color(pop)}'>#{pop_txt}</span>"

    precip_col = format('%<val>.1f %<unit>s', val: d['precip'], unit: precip_unit).rjust(7)

    cond_txt = d['cond'].to_s
    glyph = map_condition_icon(icon_map, cond_txt, true)
    icon_html = glyph.empty? ? '' : style_icon(glyph, COLOR_PRIMARY, ICON_SIZE_SM)
    cond_cell = "#{icon_html} #{CGI.escapeHTML(cond_txt)}".strip

    row = format('%-9s │ %s │ %s │ %s │ %s │ %s',
                 fmt_day_of_week(d['date']), hi_col, lo_col, pop_col, precip_col, cond_cell)
    out_rows << row
  end

  return 'No daily data' if out_rows.empty?

  "<span font_family='monospace'>#{header}\n#{out_rows.join("\n")}</span>"
end

def make_3h_table(rows, unit, precip_unit, icon_map)
  header = "<span weight='bold'>#{DETAIL3H_HEADER_TEXT}</span>"
  out = []

  rows.each do |r|
    temp_txt = "#{r['temp'].round}#{unit}".rjust(5)
    temp_col = "<span foreground='#{color_for_temp(r['temp'], unit)}'>#{temp_txt}</span>"

    pop_val = [[0, r['pop'].to_i].max, 100].min
    pop_txt = format('%3d%%', pop_val)
    pop_col = "<span foreground='#{pop_color(pop_val)}'>#{pop_txt}</span>"

    precip_col = format('%<val>.1f %<unit>s', val: r['precip'], unit: precip_unit).rjust(7)

    glyph = map_condition_icon(icon_map, r['cond'].to_s, r['is_day'] != 0)
    icon_html = glyph.empty? ? '' : style_icon(glyph, COLOR_PRIMARY, ICON_SIZE_SM)
    cond_cell = "#{icon_html} #{CGI.escapeHTML(r['cond'].to_s)}".strip

    out << format('%-9s │ %2s │ %s │ %s │ %s │ %s',
                  fmt_day_of_week(r['date']), fmt_hour(r['dt']), temp_col, pop_col, precip_col, cond_cell)
  end

  return 'No 3-hour detail' if out.empty?

  "<span font_family='monospace'>#{header}\n#{out.join("\n")}</span>"
end

def build_header_block(loc:, cond:, temp:, feels:, unit:, icon_map:, is_day:, fallback_icon:,
                       sunrise: nil, sunset: nil, now_pop: nil, precip_amt: nil, precip_unit: '')
  # Returns the exact same top block used by all tooltips.
  location_line = format('<b>%s, %s %s</b>',
                         CGI.escapeHTML(loc['name'].to_s || 'Local'),
                         CGI.escapeHTML(loc['region'].to_s || ''),
                         CGI.escapeHTML(loc['country'].to_s || ''))

  # current conditions + colored thermometer
  tglyph, tcolor = thermometer_for_temp(feels, unit)
  current_line = format('%s %s | %s%d%s (feels %d%s)',
                        style_icon(map_condition_icon(icon_map, cond, is_day != 0) || fallback_icon),
                        CGI.escapeHTML(cond),
                        style_icon(tglyph, tcolor),
                        temp.round,
                        unit,
                        feels.round,
                        unit)

  # optional sunrise/sunset
  astro_line = ''
  if sunrise || sunset
    astro_line = format('%s Sunrise %s | %s Sunset %s',
                        style_icon(SUNRISE_ICON),
                        CGI.escapeHTML(sunrise || '—'),
                        style_icon(SUNSET_ICON),
                        CGI.escapeHTML(sunset || '—'))
  end

  # optional "now" precip / PoP (colored)
  now_line = ''
  if now_pop && precip_amt && !precip_unit.empty?
    pop_icon_html = style_icon(icon_for_pop(now_pop), pop_color(now_pop))
    now_pop_col = "<span foreground='#{pop_color(now_pop)}'>#{now_pop.to_i}%</span>"
    now_line = format('%s PoP %s, Precip %.1f%s',
                      pop_icon_html, now_pop_col, precip_amt, precip_unit)
  end

  parts = [location_line, '', current_line]
  parts << astro_line unless astro_line.empty?
  parts << now_line unless now_line.empty?
  parts << "\n#{divider}\n"
  parts.join("\n")
end

def build_week_view_tooltip(loc:, cond:, temp:, feels:, unit:, icon_map:, is_day:, fallback_icon:,
                            three_hour_rows:, precip_unit:, sunrise: nil, sunset: nil,
                            now_pop: nil, precip_amt: nil, astro_by_date: nil)
  header_block = build_header_block(
    loc: loc, cond: cond, temp: temp, feels: feels, unit: unit,
    icon_map: icon_map, is_day: is_day, fallback_icon: fallback_icon,
    sunrise: sunrise, sunset: sunset, now_pop: now_pop,
    precip_amt: precip_amt, precip_unit: precip_unit
  )

  astro_table = make_astro3d_table(three_hour_rows, astro_by_date || {})
  astro_header = "<b>#{style_icon(SUNRISE_ICON, COLOR_PRIMARY, ICON_SIZE_SM)} Week Sunrise / Sunset</b>"

  detail_header = "<b>#{style_icon('󰨳', COLOR_PRIMARY, ICON_SIZE_SM)} Week Details</b>"
  detail_table = make_3h_table(three_hour_rows, unit, precip_unit, icon_map)

  "#{header_block}\n#{astro_header}\n\n#{astro_table}\n\n#{divider}\n\n#{detail_header}\n\n#{detail_table}"
end

def build_text_and_tooltip(loc:, cond:, temp:, feels:, precip_amt:, is_day:, next_hours:,
                           days:, unit:, precip_unit:, icon_map:, icon_pos:, fallback_icon:,
                           sunrise:, sunset:)
  # icon for current condition
  cond_icon_raw = map_condition_icon(icon_map, cond, is_day != 0) || fallback_icon

  # main text with waybar icon
  waybar_icon = style_icon(cond_icon_raw, COLOR_PRIMARY, ICON_SIZE_SM)
  left = "#{waybar_icon} #{temp.round}#{unit}"
  right = "#{temp.round}#{unit} #{waybar_icon}"
  text = (icon_pos || 'left') == 'left' ? left : right

  # tables
  next_hours_table = make_hour_table(next_hours, unit, precip_unit, icon_map)
  next_days_overview_table = make_day_table(days, unit, precip_unit, icon_map)

  header_block = build_header_block(
    loc: loc, cond: cond, temp: temp, feels: feels, unit: unit,
    icon_map: icon_map, is_day: is_day, fallback_icon: fallback_icon,
    sunrise: sunrise, sunset: sunset,
    now_pop: next_hours.empty? ? nil : next_hours[0]['pop'].to_i,
    precip_amt: precip_amt, precip_unit: precip_unit
  )

  tooltip = "#{header_block}\n" \
            "<b>#{style_icon('', COLOR_PRIMARY, ICON_SIZE_SM)} Next #{next_hours.length} hours</b>\n\n" \
            "#{next_hours_table}\n\n#{divider}\n\n" \
            "<b>#{style_icon('󰨳', COLOR_PRIMARY, ICON_SIZE_SM)} Week Overview</b>\n\n#{next_days_overview_table}"

  [text, tooltip]
end

# ─── Main runner ────────────────────────────────────────────────────────────
def main
  # quick mode ops (no network)
  if ARGV.length > 0
    arg = ARGV[0]
    if %w[--next --toggle].include?(arg)
      cycle_mode('next')
      return
    elsif arg == '--prev'
      cycle_mode('prev')
      return
    elsif arg == '--set' && ARGV.length > 1
      set_mode(ARGV[1])
      return
    end
  end

  script_path = __dir__

  begin
    cfg = load_config(script_path)
    mode = get_mode
    unit_c = safe(cfg, 'unit', 'Celsius') == 'Celsius'
    hours_ahead = (safe(cfg, 'hours_ahead', 24) || 24).to_i
    icon_pos = (safe(cfg, 'icon-position', 'left') || 'left').to_s
    unit = unit_c ? '°C' : '°F'
    precip_unit = unit_c ? 'mm' : 'in'

    # data
    blob = fetch_weatherapi_forecast(cfg['key'].to_s, cfg['parameters'].to_s)
    astro_by_date = build_astro_by_date(blob)
    cur = extract_current(blob, unit_c)
    next_hours = build_next_hours(blob, unit_c, cur['now_local'], hours_ahead)
    days = build_next_days(blob, unit_c, 7)
    next_3days_detailed = build_next_3days_detailed(blob, unit_c, cur['now_local'], 3)
    sunrise, sunset = get_sun_times(blob, cur['now_local'])

    # icons
    icon_map = load_icon_map(script_path)
    fallback_icon = map_condition_icon(icon_map, cur['cond'], cur['is_day'] != 0) || ''

    # Default tooltip (compact)
    text_default, tooltip_default = build_text_and_tooltip(
      loc: cur['loc'], cond: cur['cond'], temp: cur['temp'], feels: cur['feels'],
      precip_amt: cur['precip_amt'], is_day: cur['is_day'], next_hours: next_hours,
      days: days, unit: unit, precip_unit: precip_unit, icon_map: icon_map,
      icon_pos: icon_pos, fallback_icon: fallback_icon, sunrise: sunrise, sunset: sunset
    )

    # Detail tooltip (3-hour view)
    tooltip_week_view = build_week_view_tooltip(
      loc: cur['loc'], cond: cur['cond'], temp: cur['temp'], feels: cur['feels'],
      unit: unit, icon_map: icon_map, is_day: cur['is_day'], fallback_icon: fallback_icon,
      three_hour_rows: next_3days_detailed, precip_unit: precip_unit,
      sunrise: sunrise, sunset: sunset,
      now_pop: next_hours.empty? ? nil : next_hours[0]['pop'].to_i,
      precip_amt: cur['precip_amt'], astro_by_date: astro_by_date
    )

    text = text_default
    tooltip = mode == 'weekview' ? tooltip_week_view : tooltip_default

    classes = [
      'weather',
      mode == 'weekview' ? 'mode-weekview' : 'mode-default',
      next_hours.any? && next_hours[0]['pop'].to_i >= 60 ? 'pop-high' : 'pop-low'
    ]

    out = {
      text: text,
      tooltip: tooltip,
      alt: cur['cond'],
      class: classes
    }

    puts JSON.generate(out)
  rescue Net::HTTPError, SocketError, Timeout::Error
    sleep 2
    puts JSON.generate(text: '…', tooltip: 'network error; retrying')
  rescue JSON::ParserError, KeyError, StandardError => e
    puts JSON.generate(text: '', tooltip: "parse error: #{e.message}")
  end
end

main if __FILE__ == $PROGRAM_NAME
