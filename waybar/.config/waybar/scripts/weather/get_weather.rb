#!/usr/bin/env ruby
# waybar/.config/waybar/scripts/weather/get_weather.rb
# frozen_string_literal: true

# Waybar weather (Open-Meteo.com)
# - Text: current temp + icon (colored via <span>)
# - Tooltip: current details + next N hours table + up to 16-day table
# - Uses weather_icons.json mapping for WMO condition glyphs
# - Emits Waybar JSON (set return-type=json, markup=true)

require 'json'
require 'set'
require 'net/http'
require 'uri'
require 'time'
require 'cgi'
require 'fileutils'

# ─── Modules ────────────────────────────────────────────────────────────────

# A module for general-purpose helper functions
#
module Utils
  class << self
    # Loads a JSON or JSONC file and parses it.
    #
    # @param path [String] Path to the JSON/JSONC file
    # @return [Hash, Array] Parsed JSON data
    # @raise [Errno::ENOENT] If file doesn't exist
    # @raise [JSON::ParserError] If file contains invalid JSON
    def load_json(path)
      file_content = File.read(path, encoding: 'utf-8')
      content_no_comments = file_content.gsub(%r{//.*$}, '')
      JSON.parse(content_no_comments)
    end

    # Parses a value into an integer, with a fallback default.
    #
    # @param val [Object] Value to parse (Numeric, String, or nil)
    # @param default [Integer] Default value if parsing fails
    # @return [Integer] Parsed integer or default
    def parse_int(val, default = 0)
      return default if val.nil? || val == ''
      return val.to_i if val.is_a?(Numeric)
      return val.to_i if val.to_s.match?(/\A-?\d+\z/)
      return val.to_f.to_i if val.to_s.match?(/\A-?\d+\.?\d*\z/)

      default
    end

    # Parses a value into a float, with a fallback default.
    def parse_float(val, default = 0.0)
      return default if val.nil? || val == ''
      return val.to_f if val.is_a?(Numeric)
      return val.to_f if val.to_s.match?(/\A-?\d+\.?\d*\z/)

      default
    end

    # Formats a Time/DateTime object into a 2-digit hour (e.g., "08", "23").
    def fmt_hour(datetime)
      datetime.strftime('%H')
    end

    # Formats a date string (e.g., "2025-11-20") into "Day MM/DD".
    def fmt_day_of_week(datestr)
      # e.g., 'Mon 10/06'
      Time.strptime(datestr, '%Y-%m-%d').strftime('%a %m/%d')
    end
  end
end

# Main configuration, merges with user config for dynamic user settings based on json file
module Config
  @settings = {
    colors: {
      'primary' => '#42A5F5',
      'cold' => 'skyblue',
      'neutral' => '#42A5F5',
      'warm' => 'khaki',
      'hot' => 'indianred',
      'pop_low' => '#EAD7FF',
      'pop_med' => '#CFA7FF',
      'pop_high' => '#BC85FF',
      'pop_vhigh' => '#A855F7',
      'divider' => '#2B3B57'
    },
    icon_type: 'nerd_font', # 'nerd_font' | 'emoji'
    icon_position: 'left', # 'left' | 'right'
    font_size: 14, # in px
    unit: 'Celsius', # 'Celsius' | 'Fahrenheit'
    hours_ahead: 24, # max 24
    forecast_days: 10, # max 16
    latitude: 'auto', # or float
    longitude: 'auto', # or float
    refresh_interval: 900, # seconds between API calls
    pongo_size: {}
  }

  SETTING_KEY_MAP = {
    'icon_type' => :icon_type,
    'icon_position' => :icon_position,
    'font_size' => :font_size,
    'unit' => :unit,
    'hours_ahead' => :hours_ahead,
    'forecast_days' => :forecast_days,
    'latitude' => :latitude,
    'longitude' => :longitude,
    'refresh_interval' => :refresh_interval
  }.freeze

  class << self
    attr_reader :settings

    def init
      user_config = load_user_config

      # Merge colors settings
      if user_config.key?('colors') && user_config['colors'].is_a?(Hash)
        @settings[:colors].merge!(user_config['colors'])
      end

      # Handle font size calculations
      self.set_font_size = user_config['font_size'] if user_config.key?('font_size')

      # Merge other settings
      SETTING_KEY_MAP.each do |config_key, settings_key|
        @settings[settings_key] = user_config[config_key] if user_config.key?(config_key)
      end
    end

    def colors
      @settings[:colors]
    end

    def pongo_size
      @settings[:pongo_size]
    end

    def icon_set
      @settings[:icon_type]
    end

    def set_color(key, value)
      @settings[:colors][key] = value
    end

    def set_font_size=(value)
      @settings[:font_size] = value
      update_pongo_sizes
    end

    private

    def update_pongo_sizes
      current_size = @settings[:font_size]
      @settings[:pongo_size] = {
        small: (current_size - 2) * 1000,
        medium: current_size * 1000,
        large: (current_size + 4) * 1000
      }
    end

    def load_user_config
      cfg_path = File.join(__dir__, 'weather_settings.jsonc')
      data = Utils.load_json(cfg_path)
      raise 'weather_settings.jsonc must be a JSON object' unless data.is_a?(Hash)

      data
    end
  end

  update_pongo_sizes
end

# Parses temperature into glyphs and colors
module Temperature
  SEASONAL_BIAS = ENV.fetch('SEASONAL_BIAS', '1') == '1'

  THERMOMETER_ICON = {
    COLD: '',
    NEUTRAL: '',
    WARM: '',
    HOT: ''
  }.freeze

  SUMMER_MONTHS = (5..9).freeze
  SHOULDER_MONTHS = [3, 4, 10].freeze
  DEFAULT_COLD_C = 5
  DEFAULT_COLD_F = 41
  COLD_BAND    = [THERMOMETER_ICON[:COLD], Config.colors['cold']].freeze
  NEUTRAL_BAND = [THERMOMETER_ICON[:NEUTRAL], Config.colors['neutral']].freeze
  WARM_BAND    = [THERMOMETER_ICON[:WARM], Config.colors['warm']].freeze
  HOT_BAND     = [THERMOMETER_ICON[:HOT], Config.colors['hot']].freeze

  class << self
    def init(unit:, bias:, month: Time.now.month)
      @unit = unit
      @seasonal_bias_enabled = bias
      @current_month = month
      @temperature_bands = build_temperature_bands
    end

    def glyph_and_color(temp)
      found_band = @temperature_bands.find do |limit, _glyph, _color|
        temp < limit
      end
      return nil if found_band.nil?

      [found_band[1], found_band[2]]
    end

    def color(temp)
      glyph_and_color = glyph_and_color(temp)
      return unless glyph_and_color

      glyph_and_color.last
    end

    def glyph(temp)
      glyph_and_color = glyph_and_color(temp)
      return unless glyph_and_color

      glyph_and_color.first
    end

    # --- Private Helpers ---
    private

    def build_temperature_bands
      cold, neutral, warm = temperature_limits

      [
        [cold, *COLD_BAND],
        [neutral, *NEUTRAL_BAND],
        [warm,    *WARM_BAND],
        [Float::INFINITY, *HOT_BAND]
      ]
    end

    def temperature_limits
      cold_limit = calculate_cold_limit

      if celsius?
        [cold_limit, 20, 28]
      else
        [cold_limit, 68, 82]
      end
    end

    def calculate_cold_limit
      unless @seasonal_bias_enabled
        return celsius? ? DEFAULT_COLD_C : DEFAULT_COLD_F
      end

      if celsius?
        calculate_seasonal_celsius_cold_limit
      else
        calculate_seasonal_fahrenheit_cold_limit
      end
    end

    def calculate_seasonal_celsius_cold_limit
      return 10 if SUMMER_MONTHS.cover?(@current_month)
      return 8 if SHOULDER_MONTHS.include?(@current_month)

      DEFAULT_COLD_C
    end

    def calculate_seasonal_fahrenheit_cold_limit
      celsius_limit = calculate_seasonal_celsius_cold_limit
      ((celsius_limit * 9.0 / 5.0) + 32).round
    end

    def celsius?
      @unit.to_s.strip.start_with?('°C')
    end
  end
end

# Parses Precipitation (PoP) into glyphs and colors
module Precipitation
  POP_ALERT_THRESHOLD = 60

  PRECIPITATION_ICON = {
    LOW: '',
    HIGH: ''
  }.freeze

  class << self
    def color(pop)
      pop = [[0, pop.to_i].max, 100].min
      return Config.colors['pop_low'] if pop < 30   # 0–29
      return Config.colors['pop_med'] if pop < 60   # 30–59
      return Config.colors['pop_high'] if pop < 80  # 60–79

      Config.colors['pop_vhigh'] # 80–Infinity
    end

    def icon(pop)
      pop >= POP_ALERT_THRESHOLD ? PRECIPITATION_ICON[:HIGH] : PRECIPITATION_ICON[:LOW]
    end
  end
end

# Handles mode toggles to view different weather tooltips.
# Stores the current mode in XDG_STATE_HOME/waybar/weather_mode.
module WeatherMode
  DEFAULT = 'default'
  WEEKVIEW = 'weekview'
  MODES = [DEFAULT, WEEKVIEW].freeze
  DEFAULT_MODE = DEFAULT

  class << self
    # Gets the current display mode.
    #
    # @return [String] Current mode (DEFAULT or WEEKVIEW)
    def get
      mode = File.read(file_path, encoding: 'utf-8').strip
      MODES.include?(mode) ? mode : DEFAULT_MODE
    rescue Errno::ENOENT
      DEFAULT_MODE
    end

    # Sets the display mode.
    #
    # @param mode [String] Mode to set (must be in MODES)
    # @return [void]
    def set(mode)
      return unless MODES.include?(mode)

      File.write(file_path, mode, encoding: 'utf-8')
    end

    # Cycles to the next or previous mode.
    #
    # @param direction [String] 'next' or 'prev'
    # @return [void]
    def cycle(direction = 'next')
      current_index = MODES.index(get) || 0
      new_index = if direction == 'prev'
                    (current_index - 1) % MODES.length
                  else
                    (current_index + 1) % MODES.length
                  end
      set(MODES[new_index])
    end

    private

    def file_path
      state_home = ENV['XDG_STATE_HOME'] || File.expand_path('~/.local/state')
      dir = File.join(state_home, 'waybar')
      FileUtils.mkdir_p(dir)
      File.join(dir, 'weather_mode')
    end
  end
end

# Manages weather data caching to reduce API calls
module CacheManager
  class << self
    # Checks if cached data is still fresh based on refresh interval
    #
    # @param refresh_interval [Integer] Seconds before cache expires
    # @return [Boolean] True if cache exists and is fresh
    def fresh?(refresh_interval = 900)
      return false unless File.exist?(cache_file_path)

      cache = load_cache
      return false unless cache && cache['timestamp']

      age = Time.now.to_i - cache['timestamp'].to_i
      age < refresh_interval
    rescue StandardError
      false
    end

    # Loads cached weather data
    #
    # @return [Hash, nil] Cached data or nil if not available/invalid
    def load_cache
      return nil unless File.exist?(cache_file_path)

      content = File.read(cache_file_path, encoding: 'utf-8')
      JSON.parse(content)
    rescue StandardError
      nil
    end

    # Saves weather data to cache
    #
    # @param location [Hash] Location data with :lat, :lon, :location_name
    # @param weather_data [Hash] Weather data hash
    # @param units [Hash] Unit configuration hash
    # @param settings [Hash] Settings hash
    # @return [void]
    def save_cache(location:, weather_data:, units:, settings:)
      cache_data = {
        'timestamp' => Time.now.to_i,
        'settings' => {
          'latitude' => settings[:latitude],
          'longitude' => settings[:longitude],
          'unit' => settings[:unit]
        },
        'location' => location,
        'weather_data' => weather_data,
        'units' => units
      }

      File.write(cache_file_path, JSON.generate(cache_data), encoding: 'utf-8')
    rescue StandardError => e
      # Silently fail - caching is not critical
      warn "Cache write failed: #{e.message}" if ENV['DEBUG']
    end

    # Validates that cached settings match current settings
    #
    # @param settings [Hash] Current settings
    # @return [Boolean] True if settings match
    def settings_match?(settings)
      cache = load_cache
      return false unless cache && cache['settings']

      cached_settings = cache['settings']
      settings[:latitude].to_s == cached_settings['latitude'].to_s &&
        settings[:longitude].to_s == cached_settings['longitude'].to_s &&
        settings[:unit].to_s == cached_settings['unit'].to_s
    end

    private

    def cache_file_path
      state_home = ENV['XDG_STATE_HOME'] || File.expand_path('~/.local/state')
      dir = File.join(state_home, 'waybar')
      FileUtils.mkdir_p(dir)
      File.join(dir, 'weather_cache.json')
    end
  end
end

# Handles weather data fetching and parsing
module ForecastData
  class << self
    # Resolves location coordinates from settings (auto-detect or manual).
    # If latitude or longitude is set to 'auto', uses IP geolocation.
    # Otherwise returns the configured coordinates.
    #
    # @param settings [Hash] Configuration settings hash with :latitude and :longitude keys
    # @return [Hash] Location data with :lat, :lon, and :location_name keys
    # @example Auto-detect location
    #   resolve_location({latitude: 'auto', longitude: 'auto'})
    #   # => {lat: 40.7128, lon: -74.0060, location_name: "New York, NY, USA"}
    # @example Use configured location
    #   resolve_location({latitude: 51.5074, longitude: -0.1278})
    #   # => {lat: 51.5074, lon: -0.1278, location_name: nil}
    def resolve_location(settings)
      if settings[:latitude].to_s == 'auto' || settings[:longitude].to_s == 'auto'
        # Auto-detect location from IP
        geo_data = fetch_location_from_ip
        {
          lat: geo_data['lat'],
          lon: geo_data['lon'],
          location_name: geo_data['location_name']
        }
      else
        # Use configured coordinates
        {
          lat: Utils.parse_float(settings[:latitude]),
          lon: Utils.parse_float(settings[:longitude]),
          location_name: nil
        }
      end
    end

    # Fetches location from IP address using ip-api.com
    def fetch_location_from_ip
      # Use ip-api.com for free IP geolocation (no API key required)
      # Rate limit: 45 requests/minute
      url = URI('http://ip-api.com/json/?fields=lat,lon,city,regionName,country')

      response = Net::HTTP.get_response(url)
      raise "IP geolocation error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      raise 'Unexpected response from ip-api.com' unless data.is_a?(Hash)

      {
        'lat' => Utils.parse_float(data['lat']),
        'lon' => Utils.parse_float(data['lon']),
        'location_name' => "#{data['city']}, #{data['regionName']}, #{data['country']}"
      }
    end

    # Fetches weather forecast from Open-Meteo API.
    #
    # @param lat [Float] Latitude coordinate
    # @param lon [Float] Longitude coordinate
    # @param unit_c [Boolean] True for Celsius, false for Fahrenheit
    # @param forecast_days [Integer] Number of days to forecast (max 16)
    # @return [Hash] Parsed API response with current, hourly, and daily data
    # @raise [Net::HTTPError] If API request fails
    # @raise [JSON::ParserError] If response is not valid JSON
    def fetch_openmeteo_forecast(lat, lon, unit_c, forecast_days = 16)
      url = URI('https://api.open-meteo.com/v1/forecast')

      params = {
        latitude: lat,
        longitude: lon,
        current: 'temperature_2m,apparent_temperature,is_day,precipitation,weather_code',
        hourly: 'temperature_2m,precipitation_probability,precipitation,weather_code,is_day',
        daily: 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,sunrise,sunset',
        temperature_unit: unit_c ? 'celsius' : 'fahrenheit',
        precipitation_unit: unit_c ? 'mm' : 'inch',
        timezone: 'auto',
        forecast_days: forecast_days
      }
      url.query = URI.encode_www_form(params)

      response = Net::HTTP.get_response(url)
      raise "HTTP Error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      raise 'Unexpected response from Open-Meteo' unless data.is_a?(Hash)

      data
    end

    # Extracts current weather conditions from API response
    def extract_current(blob, _unit, location_name = nil)
      cur = blob['current']
      timezone = blob['timezone']

      # Parse current time in the location's timezone
      now_local = Time.parse(cur['time'])

      {
        'timezone' => timezone,
        'location_name' => location_name,
        'cond' => WeatherCode.description(cur['weather_code']),
        'code' => cur['weather_code'].to_i,
        'temp' => Utils.parse_float(cur['temperature_2m']),
        'feels' => Utils.parse_float(cur['apparent_temperature']),
        'precip_amt' => Utils.parse_float(cur['precipitation']),
        'is_day' => Utils.parse_int(cur['is_day'], 1),
        'now_local' => now_local
      }
    end

    # Builds next N hours of forecast data
    def build_next_hours(blob, now_local, limit)
      hourly = blob['hourly']
      times = hourly['time']
      temps = hourly['temperature_2m']
      pops = hourly['precipitation_probability']
      precips = hourly['precipitation']
      codes = hourly['weather_code']
      is_days = hourly['is_day']

      hours_list = []

      times.each_with_index do |time_str, i|
        dt = Time.parse(time_str)

        hours_list << {
          'dt' => dt,
          'temp' => Utils.parse_float(temps[i]),
          'pop' => Utils.parse_int(pops[i]),
          'precip' => Utils.parse_float(precips[i]),
          'cond' => WeatherCode.description(codes[i]),
          'code' => codes[i].to_i,
          'is_day' => Utils.parse_int(is_days[i], 1)
        }
      end

      next_hours = hours_list.select { |h| h['dt'] >= now_local }[0, [0, limit].max]
      next_hours = hours_list[0, [0, limit].max] if next_hours.empty? && !hours_list.empty?
      next_hours
    end

    # Builds daily forecast for next N days
    def build_next_days(blob, max_days = 16)
      daily = blob['daily']
      dates = daily['time']
      max_temps = daily['temperature_2m_max']
      min_temps = daily['temperature_2m_min']
      codes = daily['weather_code']
      precips = daily['precipitation_sum']
      pops = daily['precipitation_probability_max']
      sunrises = daily['sunrise']
      sunsets = daily['sunset']

      days = []

      dates[0...max_days].each_with_index do |date_str, i|
        days << {
          'date' => date_str,
          'max' => Utils.parse_float(max_temps[i]),
          'min' => Utils.parse_float(min_temps[i]),
          'cond' => WeatherCode.description(codes[i]),
          'code' => codes[i].to_i,
          'precip' => Utils.parse_float(precips[i]),
          'pop' => Utils.parse_int(pops[i]),
          'sunrise' => sunrises[i],
          'sunset' => sunsets[i]
        }
      end

      days
    end

    # Builds detailed 3-hour interval forecast for next N days
    def build_next_3days_detailed(blob, now_local, num_days = 3)
      hourly = blob['hourly']
      times = hourly['time']
      temps = hourly['temperature_2m']
      pops = hourly['precipitation_probability']
      precips = hourly['precipitation']
      codes = hourly['weather_code']
      is_days = hourly['is_day']

      today = now_local.strftime('%Y-%m-%d')

      rows = []
      picked_dates = Set.new

      times.each_with_index do |time_str, i|
        dt = Time.parse(time_str)
        date_str = dt.strftime('%Y-%m-%d')

        # Skip today and past dates
        next if date_str <= today

        # Only process 3-hour intervals
        next unless (dt.hour % 3).zero?

        picked_dates << date_str

        # Stop when we have enough days
        break if picked_dates.size > num_days

        rows << {
          'date' => date_str,
          'dt' => dt,
          'temp' => Utils.parse_float(temps[i]),
          'pop' => Utils.parse_int(pops[i]),
          'precip' => Utils.parse_float(precips[i]),
          'cond' => WeatherCode.description(codes[i]),
          'code' => codes[i].to_i,
          'is_day' => Utils.parse_int(is_days[i], 1)
        }
      end

      rows.sort_by { |r| [r['date'], r['dt']] }
    end

    # Builds a lookup hash mapping dates to [sunrise, sunset] times
    def build_astro_by_date(days)
      # Map 'YYYY-MM-DD' -> [sunrise_24h, sunset_24h]
      out = {}
      days.each do |d|
        date_str = d['date']
        sr = d['sunrise'] ? Time.parse(d['sunrise']).strftime('%H:%M') : ''
        ss = d['sunset'] ? Time.parse(d['sunset']).strftime('%H:%M') : ''
        out[date_str] = [sr, ss]
      end
      out
    end

    # Gets today's sunrise and sunset times
    def get_sun_times(days, now_local)
      today = now_local.strftime('%Y-%m-%d')
      days.each do |d|
        next unless d['date'] == today

        sr = d['sunrise'] ? Time.parse(d['sunrise']).strftime('%H:%M') : ''
        ss = d['sunset'] ? Time.parse(d['sunset']).strftime('%H:%M') : ''
        return [sr, ss]
      end
      ['', '']
    end
  end
end

# Handles building tooltips and tables for weather display
module TooltipBuilder
  DIVIDER_CHAR = '─'
  DIVIDER_LEN = 74

  SUN_ICON = {
    RISE: '',
    SET: '󰖚'
  }.freeze

  # Table headers
  HOUR_TABLE_HEADER_TEXT = format(
    '%<hr>-4s │ %<temp>5s │ %<pop>4s │ %<precip>7s │ Cond',
    hr: 'Hr', temp: 'Temp', pop: 'PoP', precip: 'Precip'
  )
  DAY_TABLE_HEADER_TEXT = format(
    '%-<day>9s │ %<hi>5s │ %<lo>5s │ %<pop>4s │ %<precip>7s │ Cond',
    day: 'Day', hi: 'Hi', lo: 'Lo', pop: 'PoP', precip: 'Precip'
  )

  DETAIL3H_HEADER_TEXT = format(
    '%-<date>9s │ %<hr>2s │ %<temp>5s │ %<pop>4s │ %<precip>7s │ Cond',
    date: 'Date', hr: 'Hr', temp: 'Temp', pop: 'PoP', precip: 'Precip'
  )

  ASTRO3D_HEADER_TEXT = format(
    '%-<date>9s │ %<rise>5s │ %<set>5s',
    date: 'Date', rise: 'Rise', set: 'Set'
  )

  class << self
    # --- NEW: This method's ONLY job is to build the waybar text ---
    def build_text(cond:, temp:, code:, is_day:, icon_pos:, fallback_icon:, unit:)
      # icon for current condition
      cond_icon_raw = Icons.weather_icon(code, is_day != 0) || fallback_icon

      # main text with waybar icon
      waybar_icon = Icons.style_icon(cond_icon_raw, Config.colors['primary'], Config.pongo_size[:small])
      left = "#{waybar_icon}#{temp.round}#{unit}"
      right = "#{temp.round}#{unit} #{waybar_icon}"
      (icon_pos || 'left') == 'left' ? left : right
    end

    def build_text_and_tooltip(timezone:, cond:, temp:, feels:, precip_amt:, code:, is_day:, next_hours:,
                               days:, unit:, precip_unit:, icon_pos:, fallback_icon:,
                               sunrise:, sunset:, location_name: nil, forecast_days: 16)
      # 1. Call the new method to get the text
      text = build_text(
        cond: cond, temp: temp, code: code, is_day: is_day,
        icon_pos: icon_pos, fallback_icon: fallback_icon, unit: unit
      )

      # 2. Build the tooltip (all this logic is the same as before)
      next_hours_table = make_hour_table(next_hours, unit, precip_unit)
      next_days_overview_table = make_day_table(days, unit, precip_unit)

      header_block = build_header_block(
        timezone: timezone, cond: cond, temp: temp, feels: feels, unit: unit,
        code: code, is_day: is_day, fallback_icon: fallback_icon,
        sunrise: sunrise, sunset: sunset,
        now_pop: next_hours.empty? ? nil : next_hours[0]['pop'].to_i,
        precip_amt: precip_amt, precip_unit: precip_unit, location_name: location_name
      )

      tooltip = "#{header_block}\n" \
                "<b>#{Icons.style_icon('', Config.colors['primary'],
                                       Config.pongo_size[:small])} Next #{next_hours.length} hours</b>\n\n" \
                "#{next_hours_table}\n\n#{divider}\n\n" \
                "<b>#{Icons.style_icon('󰨳', Config.colors['primary'],
                                       Config.pongo_size[:small])} Next #{forecast_days} Days</b>\n\n#{next_days_overview_table}"

      # 3. Return both
      [text, tooltip]
    end

    # Creates a divider line for tooltip formatting
    def divider(length = DIVIDER_LEN, char = DIVIDER_CHAR, color = Config.colors['divider'])
      line = char * [1, length].max
      "<span font_family='monospace' foreground='#{color}'>#{line}</span>"
    end

    # Builds a compact table for sunrise/sunset for the dates present in rows
    def make_astro3d_table(rows, astro_by_date)
      header = "<span weight='bold'>#{ASTRO3D_HEADER_TEXT}</span>"
      dates = rows.map { |r| r['date'].to_s }.uniq.sort
      lines = dates.map do |date|
        sr, ss = astro_by_date.fetch(date, ['', ''])
        sr = (sr.empty? ? '—' : sr)[0, 5]
        ss = (ss.empty? ? '—' : ss)[0, 5]
        format('%-9s │ %5s │ %5s', Utils.fmt_day_of_week(date), sr, ss)
      end

      return 'No sunrise/sunset data' if lines.empty?

      "<span font_family='monospace'>#{header}\n#{lines.join("\n")}</span>"
    end

    # Builds hourly forecast table
    def make_hour_table(next_hours, unit, precip_unit)
      header = "<span weight='bold'>#{HOUR_TABLE_HEADER_TEXT}</span>"
      rows = []

      next_hours.each do |h|
        temp_txt = "#{h['temp'].round}#{unit}".rjust(5)
        temp_col = "<span foreground='#{Temperature.color(h['temp'])}'>#{temp_txt}</span>"

        pop_txt = "#{h['pop'].to_i}%".rjust(4)
        pop_col = "<span foreground='#{Precipitation.color(h['pop'])}'>#{pop_txt}</span>"

        precip_col = format('%<val>.1f %<unit>s', val: h['precip'], unit: precip_unit).rjust(7)

        glyph = Icons.weather_icon(h['code'], h['is_day'] != 0)
        icon_html = glyph.empty? ? '' : Icons.style_icon(glyph, Config.colors['primary'], Config.pongo_size[:small])
        cond_cell = "#{icon_html} #{CGI.escapeHTML(h['cond'].to_s)}".strip

        rows << format('%-4s │ %s │ %s │ %s │ %s',
                       Utils.fmt_hour(h['dt']), temp_col, pop_col, precip_col, cond_cell)
      end

      return 'No hourly data' if rows.empty?

      "<span font_family='monospace'>#{header}\n#{rows.join("\n")}</span>"
    end

    # Builds daily forecast table
    def make_day_table(days, unit, precip_unit)
      header = "<span weight='bold'>#{DAY_TABLE_HEADER_TEXT}</span>"
      out_rows = []

      days.each do |d|
        hi_val = d['max'].round
        lo_val = d['min'].round

        hi_txt = format('%3d%s', hi_val, unit)
        lo_txt = format('%3d%s', lo_val, unit)

        hi_col = "<span foreground='#{Temperature.color(d['max'])}'>#{hi_txt}</span>"
        lo_col = "<span foreground='#{Temperature.color(d['min'])}'>#{lo_txt}</span>"

        pop = [[0, d['pop'].to_i].max, 100].min
        pop_txt = format('%3d%%', pop)
        pop_col = "<span foreground='#{Precipitation.color(pop)}'>#{pop_txt}</span>"

        precip_col = format('%<val>.1f %<unit>s', val: d['precip'], unit: precip_unit).rjust(7)

        cond_txt = d['cond'].to_s
        glyph = Icons.weather_icon(d['code'], true)
        icon_html = glyph.empty? ? '' : Icons.style_icon(glyph, Config.colors['primary'], Config.pongo_size[:small])
        cond_cell = "#{icon_html} #{CGI.escapeHTML(cond_txt)}".strip

        row = format('%-9s │ %s │ %s │ %s │ %s │ %s',
                     Utils.fmt_day_of_week(d['date']), hi_col, lo_col, pop_col, precip_col, cond_cell)
        out_rows << row
      end

      return 'No daily data' if out_rows.empty?

      "<span font_family='monospace'>#{header}\n#{out_rows.join("\n")}</span>"
    end

    # Builds 3-hour interval forecast table
    def make_3h_table(rows, unit, precip_unit)
      header = "<span weight='bold'>#{DETAIL3H_HEADER_TEXT}</span>"
      out = []

      rows.each do |r|
        temp_txt = "#{r['temp'].round}#{unit}".rjust(5)
        temp_col = "<span foreground='#{Temperature.color(r['temp'])}'>#{temp_txt}</span>"

        pop_val = [[0, r['pop'].to_i].max, 100].min
        pop_txt = format('%3d%%', pop_val)
        pop_col = "<span foreground='#{Precipitation.color(pop_val)}'>#{pop_txt}</span>"

        precip_col = format('%<val>.1f %<unit>s', val: r['precip'], unit: precip_unit).rjust(7)

        glyph = Icons.weather_icon(r['code'], r['is_day'] != 0)
        icon_html = glyph.empty? ? '' : Icons.style_icon(glyph, Config.colors['primary'], Config.pongo_size[:small])
        cond_cell = "#{icon_html} #{CGI.escapeHTML(r['cond'].to_s)}".strip

        out << format('%-9s │ %2s │ %s │ %s │ %s │ %s',
                      Utils.fmt_day_of_week(r['date']), Utils.fmt_hour(r['dt']), temp_col, pop_col, precip_col, cond_cell)
      end

      return 'No 3-hour detail' if out.empty?

      "<span font_family='monospace'>#{header}\n#{out.join("\n")}</span>"
    end

    # Builds the common header block for tooltips
    def build_header_block(timezone:, cond:, temp:, feels:, unit:, code:, is_day:, fallback_icon:,
                           sunrise: nil, sunset: nil, now_pop: nil, precip_amt: nil, precip_unit: '', location_name: nil)
      # Returns the exact same top block used by all tooltips.
      display_location = location_name || timezone || 'Local'
      location_line = format('<b>%s</b>', CGI.escapeHTML(display_location))

      # current conditions + colored thermometer
      tglyph, tcolor = Temperature.glyph_and_color(feels)
      current_line = format('%s %s | %s%d%s (feels %d%s)',
                            Icons.style_icon(Icons.weather_icon(code, is_day != 0) || fallback_icon),
                            CGI.escapeHTML(cond),
                            Icons.style_icon(tglyph, tcolor),
                            temp.round,
                            unit,
                            feels.round,
                            unit)

      # optional sunrise/sunset
      astro_line = ''
      if sunrise || sunset
        astro_line = format('%s Sunrise %s | %s Sunset %s',
                            Icons.style_icon(SUN_ICON[:RISE]),
                            CGI.escapeHTML(sunrise || '—'),
                            Icons.style_icon(SUN_ICON[:SET]),
                            CGI.escapeHTML(sunset || '—'))
      end

      # optional "now" precip / PoP (colored)
      now_line = ''
      if now_pop && precip_amt && !precip_unit.empty?
        pop_icon_html = Icons.style_icon(Precipitation.icon(now_pop), Precipitation.color(now_pop))
        now_pop_col = "<span foreground='#{Precipitation.color(now_pop)}'>#{now_pop.to_i}%</span>"
        now_line = format('%s PoP %s, Precip %.1f%s',
                          pop_icon_html, now_pop_col, precip_amt, precip_unit)
      end

      parts = [location_line, '', current_line]
      parts << astro_line unless astro_line.empty?
      parts << now_line unless now_line.empty?
      parts << "\n#{divider}\n"
      parts.join("\n")
    end

    # Builds week view tooltip with detailed 3-hour forecast
    def build_week_view_tooltip(timezone:, cond:, temp:, feels:, unit:, code:, is_day:, fallback_icon:,
                                three_hour_rows:, precip_unit:, sunrise: nil, sunset: nil,
                                now_pop: nil, precip_amt: nil, astro_by_date: nil, location_name: nil)
      header_block = build_header_block(
        timezone: timezone, cond: cond, temp: temp, feels: feels, unit: unit,
        code: code, is_day: is_day, fallback_icon: fallback_icon,
        sunrise: sunrise, sunset: sunset, now_pop: now_pop,
        precip_amt: precip_amt, precip_unit: precip_unit, location_name: location_name
      )

      astro_table = make_astro3d_table(three_hour_rows, astro_by_date || {})
      astro_header = "<b>#{Icons.style_icon(SUN_ICON[:RISE], Config.colors['primary'],
                                            Config.pongo_size[:small])} Week Sunrise / Sunset</b>"

      detail_header = "<b>#{Icons.style_icon('󰨳', Config.colors['primary'],
                                             Config.pongo_size[:small])} Week Details</b>"
      detail_table = make_3h_table(three_hour_rows, unit, precip_unit)

      "#{header_block}\n#{astro_header}\n\n#{astro_table}\n\n#{divider}\n\n#{detail_header}\n\n#{detail_table}"
    end
  end
end

# Handles Icons in terms of mapping via weather_code or styling icon
module Icons
  class << self
    def init
      @icon_map = load_icon_map(__dir__)
    end

    def weather_icon(code, is_day)
      code = code.to_i

      @icon_map.each do |item|
        next unless item['code'].to_i == code

        return is_day ? (item['icon'] || '') : (item['icon-night'] || '')
      end

      ''
    end

    def style_icon(glyph, color = Config.colors['primary'], size = Config.pongo_size[:medium])
      "<span foreground='#{color}' size='#{size}'>#{glyph} </span>"
    end

    private

    def load_icon_map(script_path)
      data = Utils.load_json(File.join(script_path, 'weather_icons.json'))
      data.is_a?(Array) ? data : []
    rescue StandardError
      []
    end
  end
end

# View building strategies using the Strategy pattern.
# Delegates to appropriate builder based on display mode.
module ViewBuilder
  class << self
    # Builds view output by selecting the appropriate strategy.
    #
    # @param mode [String] Display mode (WeatherMode::DEFAULT or WeatherMode::WEEKVIEW)
    # @param weather_data [Hash] Weather data including :cur, :days, :next_hours, etc.
    # @param settings [Hash] Configuration settings
    # @param unit [String] Temperature unit ('°C' or '°F')
    # @param precip_unit [String] Precipitation unit ('mm' or 'in')
    # @return [Array<String, String>] Text and tooltip strings for waybar display
    def build(mode, weather_data, settings, unit, precip_unit)
      builder = mode == WeatherMode::WEEKVIEW ? WeekViewBuilder : DefaultViewBuilder
      builder.build(weather_data, settings, unit, precip_unit)
    end
  end
end

# Default view builder strategy - shows current conditions, hourly forecast, and daily overview.
module DefaultViewBuilder
  class << self
    # Builds the default view with hourly and daily forecast tables.
    #
    # @param weather_data [Hash] Weather data hash
    # @param settings [Hash] Configuration settings
    # @param unit [String] Temperature unit
    # @param precip_unit [String] Precipitation unit
    # @return [Array<String, String>] Text and tooltip
    def build(weather_data, settings, unit, precip_unit)
      cur = weather_data[:cur]
      days = weather_data[:days]
      next_hours = weather_data[:next_hours]
      sunrise = weather_data[:sunrise]
      sunset = weather_data[:sunset]
      fallback_icon = weather_data[:fallback_icon]

      TooltipBuilder.build_text_and_tooltip(
        timezone: cur['timezone'], cond: cur['cond'], temp: cur['temp'], feels: cur['feels'],
        precip_amt: cur['precip_amt'], code: cur['code'], is_day: cur['is_day'], next_hours: next_hours,
        days: days, unit: unit, precip_unit: precip_unit,
        icon_pos: settings[:icon_position], fallback_icon: fallback_icon, sunrise: sunrise, sunset: sunset,
        location_name: cur['location_name'], forecast_days: settings[:forecast_days]
      )
    end
  end
end

# Week view builder strategy - shows detailed 3-hour interval forecast and sunrise/sunset times.
module WeekViewBuilder
  class << self
    # Builds the week view with 3-hour intervals and astronomy data.
    #
    # @param weather_data [Hash] Weather data hash
    # @param settings [Hash] Configuration settings
    # @param unit [String] Temperature unit
    # @param precip_unit [String] Precipitation unit
    # @return [Array<String, String>] Text and tooltip
    def build(weather_data, settings, unit, precip_unit)
      cur = weather_data[:cur]
      next_hours = weather_data[:next_hours]
      sunrise = weather_data[:sunrise]
      sunset = weather_data[:sunset]
      fallback_icon = weather_data[:fallback_icon]
      blob = weather_data[:blob]
      days = weather_data[:days]

      next_3days = ForecastData.build_next_3days_detailed(blob, cur['now_local'], 3)
      astro_by_date = ForecastData.build_astro_by_date(days)

      text = TooltipBuilder.build_text(
        cond: cur['cond'], temp: cur['temp'], code: cur['code'], is_day: cur['is_day'],
        icon_pos: settings[:icon_position], fallback_icon: fallback_icon, unit: unit
      )

      tooltip = TooltipBuilder.build_week_view_tooltip(
        timezone: cur['timezone'], cond: cur['cond'], temp: cur['temp'], feels: cur['feels'],
        unit: unit, code: cur['code'], is_day: cur['is_day'], fallback_icon: fallback_icon,
        three_hour_rows: next_3days, precip_unit: precip_unit,
        sunrise: sunrise, sunset: sunset,
        now_pop: next_hours.empty? ? nil : next_hours[0]['pop'].to_i,
        precip_amt: cur['precip_amt'], astro_by_date: astro_by_date,
        location_name: cur['location_name']
      )

      [text, tooltip]
    end
  end
end

# Parses weather code descriptions
module WeatherCode
  WMO_CODE_DESCRIPTIONS = {
    0 => 'Clear sky',
    1 => 'Mainly clear',
    2 => 'Partly cloudy',
    3 => 'Overcast',
    45 => 'Fog',
    48 => 'Depositing rime fog',
    51 => 'Light drizzle',
    53 => 'Moderate drizzle',
    55 => 'Dense drizzle',
    56 => 'Light freezing drizzle',
    57 => 'Dense freezing drizzle',
    61 => 'Slight rain',
    63 => 'Moderate rain',
    65 => 'Heavy rain',
    66 => 'Light freezing rain',
    67 => 'Heavy freezing rain',
    71 => 'Slight snow fall',
    73 => 'Moderate snow fall',
    75 => 'Heavy snow fall',
    77 => 'Snow grains',
    80 => 'Slight rain showers',
    81 => 'Moderate rain showers',
    82 => 'Violent rain showers',
    85 => 'Slight snow showers',
    86 => 'Heavy snow showers',
    95 => 'Thunderstorm',
    96 => 'Thunderstorm with slight hail',
    99 => 'Thunderstorm with heavy hail'
  }.freeze

  class << self
    def description(code)
      WMO_CODE_DESCRIPTIONS[code.to_i] || 'Unknown'
    end
  end
end

# ─── Main runner ────────────────────────────────────────────────────────────
def main
  if ARGV.empty?
    run_weather_update
  else
    handle_cli_args(ARGV)
  end
end

private def handle_cli_args(args)
  arg = args[0]
  if %w[--next --toggle].include?(arg)
    WeatherMode.cycle
  elsif arg == '--prev'
    WeatherMode.cycle('prev')
  elsif arg == '--set' && args.length > 1
    WeatherMode.set(args[1])
  else
    run_weather_update
  end
end

# Initialize configuration modules
private def initialize_app_config(settings)
  Config.init
  Icons.init

  unit_c = settings[:unit] == 'Celsius'
  unit = unit_c ? '°C' : '°F'
  precip_unit = unit_c ? 'mm' : 'in'

  Temperature.init(
    unit: unit,
    bias: Temperature::SEASONAL_BIAS,
    month: Time.now.month
  )

  { unit_c: unit_c, unit: unit, precip_unit: precip_unit }
end

# Fetch and build all weather data structures
private def fetch_weather_data(lat, lon, settings, unit_c, location_name, unit)
  blob = ForecastData.fetch_openmeteo_forecast(lat, lon, unit_c, settings[:forecast_days])
  cur = ForecastData.extract_current(blob, unit, location_name)
  days = ForecastData.build_next_days(blob, settings[:forecast_days])
  next_hours = ForecastData.build_next_hours(blob, cur['now_local'], settings[:hours_ahead])
  sunrise, sunset = ForecastData.get_sun_times(days, cur['now_local'])
  fallback_icon = Icons.weather_icon(cur['code'], cur['is_day'] != 0) || ''

  { blob: blob, cur: cur, days: days, next_hours: next_hours, sunrise: sunrise, sunset: sunset,
    fallback_icon: fallback_icon }
end

# Generate text and tooltip based on mode (using Strategy pattern)
private def generate_output(mode, weather_data, settings, unit, precip_unit)
  ViewBuilder.build(mode, weather_data, settings, unit, precip_unit)
end

# Recursively converts hash string keys to symbols, handling nested structures
private def symbolize_keys(obj)
  case obj
  when Hash
    obj.transform_keys(&:to_sym).transform_values { |v| symbolize_keys(v) }
  when Array
    obj.map { |item| symbolize_keys(item) }
  else
    obj
  end
end

# Converts cached weather data structure to use symbol keys
# Note: Only symbolize top-level keys; keep nested structures with string keys
# as the existing code expects string keys for accessing nested data
private def symbolize_weather_data(data)
  return data unless data.is_a?(Hash)

  result = data.transform_keys(&:to_sym)

  # Restore Time objects that were serialized as strings
  if result[:cur] && result[:cur]['now_local'].is_a?(String)
    result[:cur]['now_local'] = Time.parse(result[:cur]['now_local'])
  end

  # Restore Time objects in hourly forecast
  if result[:next_hours].is_a?(Array)
    result[:next_hours].each do |hour|
      hour['dt'] = Time.parse(hour['dt']) if hour['dt'].is_a?(String)
    end
  end

  result
end

# Main application logic orchestrator
private def run_weather_update(force_refresh: false)
  settings = Config.settings
  mode = WeatherMode.get
  units = initialize_app_config(settings)

  # Check cache freshness and settings match
  refresh_interval = settings[:refresh_interval] || 900
  use_cache = !force_refresh &&
              CacheManager.fresh?(refresh_interval) &&
              CacheManager.settings_match?(settings)

  if use_cache
    # Load from cache
    cache = CacheManager.load_cache
    location = symbolize_keys(cache['location'])
    weather_data = symbolize_weather_data(cache['weather_data'])
    # Update units from cache to ensure consistency
    units = symbolize_keys(cache['units'])
  else
    # Fetch fresh data from API
    location = ForecastData.resolve_location(settings)
    weather_data = fetch_weather_data(
      location[:lat], location[:lon], settings,
      units[:unit_c], location[:location_name], units[:unit]
    )
    # Save to cache
    CacheManager.save_cache(
      location: location,
      weather_data: weather_data,
      units: units,
      settings: settings
    )
  end

  text, tooltip = generate_output(mode, weather_data, settings, units[:unit], units[:precip_unit])
  classes = [
    'weather',
    mode == WeatherMode::WEEKVIEW ? 'mode-weekview' : 'mode-default',
    weather_data[:next_hours].any? && weather_data[:next_hours][0]['pop'].to_i >= 60 ? 'pop-high' : 'pop-low'
  ]
  out = { text: text, tooltip: tooltip, alt: weather_data[:cur]['cond'], class: classes }
  puts JSON.generate(out)

# --- Error Handling ---
rescue Net::HTTPError, SocketError, Timeout::Error => e
  sleep 2
  puts JSON.generate(text: '…', tooltip: "network error: #{e.message}")
rescue JSON::ParserError, KeyError => e
  puts JSON.generate(text: '', tooltip: "parse error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
rescue StandardError => e
  puts JSON.generate(text: '!', tooltip: "unexpected error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
end

main if __FILE__ == $PROGRAM_NAME
