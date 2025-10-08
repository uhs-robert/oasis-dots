#!/usr/bin/env python3
# waybar/.config/waybar/scripts/weather-api/get_weather_api.py
# -*- coding: utf-8 -*-
"""
Waybar weather (WeatherAPI.com)
- Text: current temp + icon (colored via <span>)
- Tooltip: current details + next N hours table + up to 7-day table
- Uses your weather_icons.json mapping for the condition glyph
- Emits Waybar JSON (set return-type=json, markup=true)

Config file (same dir): weather_settings.json
{
  "key": "YOUR_WEATHERAPI_KEY",
  "parameters": "40.71,-74.01",      // "lat,lon" or "City"
  "unit": "Fahrenheit",               // or "Celsius"
  "icon-position": "left",            // or "right"
  "hours_ahead": 6                    // # of hourly rows to show
}
"""

from __future__ import annotations

import sys
import html
import json
import os
import time
from datetime import datetime
from typing import Any, Dict, List, Tuple

import requests

# ─── Constants ──────────────────────────────────────────────────────────────
COLOR_PRIMARY: str = "#42A5F5"
ICON_SIZE: str = "14000"  # pango units; ~14pt
ICON_SIZE_LG: str = "18000"
ICON_SIZE_SM: str = "12000"
POP_ALERT_THRESHOLD: int = 60
POP_ICON_HIGH: str = ""
POP_ICON_LOW: str = ""
SUNRISE_ICON: str = ""
SUNSET_ICON: str = "󰖚"
THERMO_COLD = ""
THERMO_NEUTRAL = ""
THERMO_WARM = ""
THERMO_HOT = ""
COLOR_COLD = "skyblue"
COLOR_NEUTRAL = COLOR_PRIMARY
COLOR_WARM = "khaki"
COLOR_HOT = "indianred"
COLOR_POP_LOW = "#EAD7FF"
COLOR_POP_MED = "#CFA7FF"
COLOR_POP_HIGH = "#BC85FF"
COLOR_POP_VHIGH = "#A855F7"
COLOR_DIVIDER = "#2B3B57"
DIVIDER_CHAR = "─"
DIVIDER_LEN = 74
HOUR_TABLE_HEADER_TEXT: str = (
    f"{'Hr':<4} │ {'Temp':>5} │ {'PoP':>4} │ {'Precip':>7} │ Cond"
)
DAY_TABLE_HEADER_TEXT: str = (
    f"{'Day':<9} │ {'Hi':>5} │ {'Lo':>5} │ {'PoP':>4} │ {'Precip':>7} │ Cond"
)
DETAIL3H_HEADER_TEXT: str = (
    f"{'Date':<9} │ {'Hr':>2} │ {'Temp':>5} │ {'PoP':>4} │ {'Precip':>7} │ Cond"
)
ASTRO3D_HEADER_TEXT: str = f"{'Date':<9} │ {'Rise':>5} │ {'Set':>5}"


# ─── Utilities ──────────────────────────────────────────────────────────────
def safe(d: Dict[str, Any], k: str, default: Any = None) -> Any:
    return d[k] if k in d else default


def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def divider(
    length: int = DIVIDER_LEN, char: str = DIVIDER_CHAR, color: str = COLOR_DIVIDER
) -> str:
    line = char * max(1, length)
    return f"<span font_family='monospace' foreground='{color}'>{line}</span>"


def to_int(val: Any, default: int = 0) -> int:
    try:
        return int(val)  # handles "60", 60
    except Exception:
        try:
            return int(float(val))  # handles "60.0"
        except Exception:
            return default


def to_float(val: Any, default: float = 0.0) -> float:
    try:
        return float(val)
    except Exception:
        return default


def fmt_h(dt: datetime) -> str:
    return dt.strftime("%H")


def fmt_dow(datestr: str) -> str:
    # e.g., 'Mon 10/06'
    return datetime.strptime(datestr, "%Y-%m-%d").strftime("%a %m/%d")


def _fmt_astro_24h(t: str) -> str:
    """WeatherAPI astro times come as '07:01 AM' local. Return '07:01' (24h)."""
    try:
        return datetime.strptime(t.strip(), "%I:%M %p").strftime("%H:%M")
    except Exception:
        return t.strip()


def get_sun_times(blob: Dict[str, Any], now_local: datetime) -> Tuple[str, str]:
    """Find today's sunrise/sunset from forecastday[].astro."""
    fc = safe(blob, "forecast", {}).get("forecastday", [])
    today = now_local.strftime("%Y-%m-%d")
    for d in fc:
        if str(safe(d, "date", "")) == today:
            astro = safe(d, "astro", {})
            sr = _fmt_astro_24h(str(safe(astro, "sunrise", "")))
            ss = _fmt_astro_24h(str(safe(astro, "sunset", "")))
            return sr, ss
    return "", ""


def icon_for_pop(pop: int) -> str:
    return POP_ICON_HIGH if pop >= POP_ALERT_THRESHOLD else POP_ICON_LOW


def _is_celsius_unit(unit: str) -> bool:
    return str(unit).strip().startswith("°C")


def thermometer_for_temp(temp: float, unit: str) -> tuple[str, str]:
    """
    Return (glyph, color) based on temp and unit.
    Bands:
      °F:  <41=cold, 41–67=neutral, 68–81=warm, ≥82=hot
      °C:  <5=cold,  5–19=neutral, 20–27=warm,  ≥28=hot
    """
    if _is_celsius_unit(unit):
        if temp < 5:
            return THERMO_COLD, COLOR_COLD
        if temp < 20:
            return THERMO_NEUTRAL, COLOR_NEUTRAL
        if temp < 28:
            return THERMO_WARM, COLOR_WARM
        return THERMO_HOT, COLOR_HOT
    else:
        if temp < 41:
            return THERMO_COLD, COLOR_COLD
        if temp < 68:
            return THERMO_NEUTRAL, COLOR_NEUTRAL
        if temp < 82:
            return THERMO_WARM, COLOR_WARM
        return THERMO_HOT, COLOR_HOT


def color_for_temp(val: float, unit: str) -> str:
    return thermometer_for_temp(val, unit)[1]


def pop_color(pop: int) -> str:
    pop = max(0, min(100, int(pop)))
    if pop < 30:
        return COLOR_POP_LOW  # 0–29
    if pop < 60:
        return COLOR_POP_MED  # 30–59
    if pop < 80:
        return COLOR_POP_HIGH  # 60–79
    return COLOR_POP_VHIGH  # 80–100


def _mode_file() -> str:
    state_home = os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
    d = os.path.join(state_home, "waybar")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, "weather_mode")


def get_mode() -> str:
    try:
        with open(_mode_file(), "r", encoding="utf-8") as f:
            m = f.read().strip()
            return m if m in {"default", "weekview"} else "default"
    except Exception:
        return "default"


def set_mode(m: str) -> None:
    with open(_mode_file(), "w", encoding="utf-8") as f:
        f.write(m)


def cycle_mode(direction: str = "next") -> None:
    modes = ["default", "weekview"]
    cur = get_mode()
    i = modes.index(cur) if cur in modes else 0
    if direction == "prev":
        i = (i - 1) % len(modes)
    else:  # next/toggle
        i = (i + 1) % len(modes)
    set_mode(modes[i])


def build_astro_by_date(blob: Dict[str, Any]) -> Dict[str, Tuple[str, str]]:
    """Map 'YYYY-MM-DD' -> (sunrise_24h, sunset_24h) for all forecast days."""
    out: Dict[str, Tuple[str, str]] = {}
    for d in safe(safe(blob, "forecast", {}), "forecastday", []):
        date_str = str(safe(d, "date", ""))
        astro = safe(d, "astro", {})
        sr = _fmt_astro_24h(str(safe(astro, "sunrise", "")))
        ss = _fmt_astro_24h(str(safe(astro, "sunset", "")))
        out[date_str] = (sr, ss)
    return out


def make_astro3d_table(
    rows: List[Dict[str, Any]], astro_by_date: Dict[str, Tuple[str, str]]
) -> str:
    """Build a compact table for sunrise/sunset for the dates present in rows."""
    header = f"<span weight='bold'>{ASTRO3D_HEADER_TEXT}</span>"
    dates = sorted({str(r["date"]) for r in rows})
    lines = []
    for date in dates:
        sr, ss = astro_by_date.get(date, ("", ""))
        sr, ss = (sr or "—")[:5], (ss or "—")[:5]
        lines.append(f"{fmt_dow(date):<9} │ {sr:>5} │ {ss:>5}")
    return (
        f"<span font_family='monospace'>{header}\n" + "\n".join(lines) + "</span>"
        if lines
        else "No sunrise/sunset data"
    )


# ─── Icons ──────────────────────────────────────────────────────────────────
def load_icon_map(script_path: str) -> List[Dict[str, Any]]:
    try:
        data = load_json(os.path.join(script_path, "weather_icons.json"))
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _norm(s: str) -> str:
    return str(s).strip().lower()


def _to_set(v) -> set[str]:
    if v is None:
        return set()
    if isinstance(v, (list, tuple)):
        return {_norm(x) for x in v}
    return {_norm(v)}


def map_condition_icon(icon_map: List[Dict[str, Any]], text: str, is_day: bool) -> str:
    t = _norm(text)
    # exact day/night bucket match
    for item in icon_map:
        day_set = _to_set(item.get("day"))
        night_set = _to_set(item.get("night"))
        if is_day and t in day_set:
            return item.get("icon", "")
        if not is_day and t in night_set:
            return item.get("icon-night", "")

    # fallback: any match regardless of bucket
    for item in icon_map:
        if t in (_norm(item.get("day")), _norm(item.get("night"))):
            return item.get("icon", "") if is_day else item.get("icon-night", "")

    # final synonym fallback
    if t == "clear" and not is_day:
        # try to reuse the Sunny entry for night if present
        for item in icon_map:
            if _norm(item.get("day")) == "sunny":
                return item.get("icon-night", "") or item.get("icon", "")
    if t == "sunny" and is_day:
        for item in icon_map:
            if _norm(item.get("day")) == "sunny":
                return item.get("icon", "")
    return ""


def style_icon(glyph: str, color: str = COLOR_PRIMARY, size: str = ICON_SIZE) -> str:
    return f"<span foreground='{color}' size='{size}'>{glyph} </span>"


# ─── Data fetch / parse ─────────────────────────────────────────────────────
def load_config(script_path: str) -> Dict[str, Any]:
    cfg_path = os.path.join(script_path, "weather_settings.json")
    data = load_json(cfg_path)
    if not isinstance(data, dict):
        raise ValueError("weather_settings.json must be a JSON object")
    return data


def fetch_weatherapi_forecast(key: str, q: str) -> Dict[str, Any]:
    url = "http://api.weatherapi.com/v1/forecast.json"
    params = {"key": key, "q": q, "days": 7, "aqi": "no", "alerts": "no"}
    r = requests.get(url, params=params, timeout=8)
    r.raise_for_status()
    data = r.json()
    if not isinstance(data, dict):
        raise ValueError("Unexpected response from WeatherAPI")
    return data


def extract_current(blob: Dict[str, Any], unit_c: bool) -> Dict[str, Any]:
    loc = blob["location"]
    cur = blob["current"]
    cond = str(cur["condition"]["text"])
    temp = to_float(cur["temp_c"] if unit_c else cur["temp_f"])
    feels = to_float(cur["feelslike_c"] if unit_c else cur["feelslike_f"])
    precip_amt = to_float(cur.get("precip_mm") if unit_c else cur.get("precip_in"))
    is_day = 1 if to_int(cur.get("is_day"), 1) == 1 else 0
    # naive local time (matches our hourly timestamps below)
    now_local = datetime.strptime(str(loc["localtime"]), "%Y-%m-%d %H:%M")
    return {
        "loc": loc,
        "cond": cond,
        "temp": temp,
        "feels": feels,
        "precip_amt": precip_amt,
        "is_day": is_day,
        "now_local": now_local,
    }


def build_next_hours(
    blob: Dict[str, Any], unit_c: bool, now_local: datetime, limit: int
) -> List[Dict[str, Any]]:
    fc = blob["forecast"]["forecastday"]
    hours_list: List[Dict[str, Any]] = []
    for d in fc[:2]:  # up to ~48 hours
        for h in d["hour"]:
            dt = datetime.fromtimestamp(to_int(h["time_epoch"]))
            hours_list.append(
                {
                    "dt": dt,
                    "pop": to_int(h.get("chance_of_rain")),
                    "precip": to_float(
                        h.get("precip_mm") if unit_c else h.get("precip_in")
                    ),
                    "temp": to_float(h["temp_c"] if unit_c else h["temp_f"]),
                    "cond": str(h["condition"]["text"]),
                    "is_day": 1 if to_int(h.get("is_day"), 1) == 1 else 0,  # NEW
                }
            )

    next_hours = [h for h in hours_list if h["dt"] >= now_local][: max(0, limit)]
    if not next_hours and hours_list:
        next_hours = hours_list[: max(0, limit)]
    return next_hours


def build_next_days(
    blob: Dict[str, Any], unit_c: bool, max_days: int = 7
) -> List[Dict[str, Any]]:
    fc = blob["forecast"]["forecastday"]
    days: List[Dict[str, Any]] = []
    for d in fc[:max_days]:
        day = d["day"]
        days.append(
            {
                "date": str(d["date"]),
                "pop": to_int(day.get("daily_chance_of_rain")),
                "max": to_float(day["maxtemp_c"] if unit_c else day["maxtemp_f"]),
                "min": to_float(day["mintemp_c"] if unit_c else day["mintemp_f"]),
                "cond": str(day["condition"]["text"]),
                "precip": to_float(
                    day.get("totalprecip_mm") if unit_c else day.get("totalprecip_in")
                ),
            }
        )
    return days


def build_next_3days_detailed(
    blob: Dict[str, Any], unit_c: bool, now_local: datetime, num_days: int = 3
) -> List[Dict[str, Any]]:
    fc = blob["forecast"]["forecastday"]
    today = now_local.strftime("%Y-%m-%d")

    rows: List[Dict[str, Any]] = []
    picked = 0
    for d in fc:
        date_str = str(d["date"])
        if date_str <= today:
            continue  # skip today and any past
        # take this day
        picked += 1
        for h in d["hour"]:
            # dt is local time per WeatherAPI
            dt = datetime.fromtimestamp(to_int(h["time_epoch"]))
            if dt.hour % 3 != 0:
                continue  # downsample to 3h grid
            rows.append(
                {
                    "date": date_str,
                    "dt": dt,
                    "temp": to_float(h["temp_c"] if unit_c else h["temp_f"]),
                    "pop": to_int(h.get("chance_of_rain")),
                    "precip": to_float(
                        h.get("precip_mm") if unit_c else h.get("precip_in")
                    ),
                    "cond": str(h["condition"]["text"]),
                    "is_day": 1 if to_int(h.get("is_day"), 1) == 1 else 0,
                }
            )
        if picked >= num_days:
            break

    # stable ordering: by date, then time
    rows.sort(key=lambda r: (r["date"], r["dt"]))
    return rows


# ─── Tables & Tooltip ───────────────────────────────────────────────────────
def make_hour_table(next_hours, unit, precip_unit, icon_map) -> str:
    header = f"<span weight='bold'>{HOUR_TABLE_HEADER_TEXT}</span>"
    rows = []
    for h in next_hours:
        # build padded text first so spans don't affect width
        temp_txt = f"{int(round(h['temp']))}{unit}".rjust(5)
        temp_col = (
            f"<span foreground='{color_for_temp(h['temp'], unit)}'>{temp_txt}</span>"
        )

        pop_txt = f"{int(h['pop'])}%".rjust(4)
        pop_col = f"<span foreground='{pop_color(h['pop'])}'>{pop_txt}</span>"
        precip_col = f"{h['precip']:.1f} {precip_unit}".rjust(7)
        glyph = map_condition_icon(icon_map, str(h["cond"]), bool(h.get("is_day", 1)))
        icon_html = style_icon(glyph, COLOR_PRIMARY, ICON_SIZE_SM) if glyph else ""
        cond_cell = f"{icon_html} {html.escape(str(h['cond']))}".strip()

        rows.append(
            f"{fmt_h(h['dt']):<4} │ {temp_col} │ {pop_col} │ {precip_col} │ {cond_cell}"
        )

    return (
        f"<span font_family='monospace'>{header}\n" + "\n".join(rows) + "</span>"
        if rows
        else "No hourly data"
    )


def make_day_table(days, unit, precip_unit, icon_map) -> str:
    header = f"<span weight='bold'>{DAY_TABLE_HEADER_TEXT}</span>"
    out_rows = []
    for d in days:
        hi_val = round(d["max"])
        lo_val = round(d["min"])

        # build padded strings before wrapping in spans
        hi_txt = f"{int(hi_val):>3}{unit}"
        lo_txt = f"{int(lo_val):>3}{unit}"

        hi_col = f"<span foreground='{color_for_temp(d['max'], unit)}'>{hi_txt}</span>"
        lo_col = f"<span foreground='{color_for_temp(d['min'], unit)}'>{lo_txt}</span>"

        pop = max(0, min(100, int(d["pop"])))
        pop_txt = f"{pop:>3}%"
        pop_col = f"<span foreground='{pop_color(pop)}'>{pop_txt}</span>"
        precip_col = f"{d['precip']:.1f} {precip_unit}".rjust(7)
        cond_txt = str(d["cond"])
        glyph = map_condition_icon(icon_map, cond_txt, True)
        icon_html = style_icon(glyph, COLOR_PRIMARY, ICON_SIZE_SM) if glyph else ""
        cond_cell = f"{icon_html} {html.escape(cond_txt)}".strip()

        row = (
            f"{fmt_dow(d['date']):<9} │ "
            f"{hi_col} │ "
            f"{lo_col} │ "
            f"{pop_col} │ "
            f"{precip_col} │ "
            f"{cond_cell}"
        )
        out_rows.append(row)

    return (
        f"<span font_family='monospace'>{header}\n" + "\n".join(out_rows) + "</span>"
        if out_rows
        else "No daily data"
    )


def make_3h_table(
    rows: List[Dict[str, Any]], unit: str, precip_unit: str, icon_map
) -> str:
    header = f"<span weight='bold'>{DETAIL3H_HEADER_TEXT}</span>"
    out = []
    for r in rows:
        # Temp (pad then color)
        temp_txt = f"{int(round(r['temp']))}{unit}".rjust(5)
        temp_col = (
            f"<span foreground='{color_for_temp(r['temp'], unit)}'>{temp_txt}</span>"
        )

        # PoP (pad then color)
        pop_val = max(0, min(100, int(r["pop"])))
        pop_txt = f"{pop_val:>3}%"
        pop_col = f"<span foreground='{pop_color(pop_val)}'>{pop_txt}</span>"

        precip_col = f"{float(r['precip']):.1f} {precip_unit}".rjust(7)

        glyph = map_condition_icon(icon_map, str(r["cond"]), bool(r.get("is_day", 1)))
        icon_html = style_icon(glyph, COLOR_PRIMARY, ICON_SIZE_SM) if glyph else ""
        cond_cell = f"{icon_html} {html.escape(str(r['cond']))}".strip()

        out.append(
            f"{fmt_dow(r['date']):<9} │ {fmt_h(r['dt']):>2} │ {temp_col} │ {pop_col} │ {precip_col} │ {cond_cell}"
        )

    return (
        f"<span font_family='monospace'>{header}\n" + "\n".join(out) + "</span>"
        if out
        else "No 3-hour detail"
    )


def build_header_block(
    loc: Dict[str, Any],
    cond: str,
    temp: float,
    feels: float,
    unit: str,
    icon_map: List[Dict[str, Any]],
    is_day: int,
    fallback_icon: str,
    sunrise: str | None = None,
    sunset: str | None = None,
    now_pop: int | None = None,
    precip_amt: float | None = None,
    precip_unit: str = "",
) -> str:
    """Returns the exact same top block used by all tooltips."""
    location_line = (
        f"<b>{html.escape(str(loc.get('name', 'Local')))}, "
        f"{html.escape(str(loc.get('region', '')))} "
        f"{html.escape(str(loc.get('country', '')))}</b>"
    )

    # current conditions + colored thermometer
    tglyph, tcolor = thermometer_for_temp(temp, unit)
    current_line = (
        f"{style_icon(map_condition_icon(icon_map, cond, bool(is_day)) or fallback_icon)} "
        f"{html.escape(cond)} | {style_icon(tglyph, tcolor)}{int(round(temp))}{unit} "
        f"(feels {int(round(feels))}{unit})"
    )

    # optional sunrise/sunset
    astro_line = ""
    if sunrise or sunset:
        astro_line = (
            f"{style_icon(SUNRISE_ICON)} Sunrise {html.escape(sunrise or '—')} | "
            f"{style_icon(SUNSET_ICON)} Sunset {html.escape(sunset or '—')}"
        )

    # optional “now” precip / PoP (colored)
    now_line = ""
    if now_pop is not None and precip_amt is not None and precip_unit:
        pop_icon_html = style_icon(icon_for_pop(now_pop), pop_color(now_pop))
        now_pop_col = f"<span foreground='{pop_color(now_pop)}'>{int(now_pop)}%</span>"
        now_line = (
            f"{pop_icon_html} PoP {now_pop_col}, Precip {precip_amt:.1f}{precip_unit}"
        )

    parts = [location_line, "", current_line]
    if astro_line:
        parts.append(astro_line)
    if now_line:
        parts.append(now_line)
    parts.append(f"\n{divider()}\n")
    return "\n".join(parts)


def build_week_view_tooltip(
    loc: Dict[str, Any],
    cond: str,
    temp: float,
    feels: float,
    unit: str,
    icon_map: List[Dict[str, Any]],
    is_day: int,
    fallback_icon: str,
    three_hour_rows: List[Dict[str, Any]],
    precip_unit: str,
    sunrise: str | None = None,
    sunset: str | None = None,
    now_pop: int | None = None,
    precip_amt: float | None = None,
    astro_by_date: Dict[str, Tuple[str, str]] | None = None,  # ← NEW
) -> str:
    header_block = build_header_block(
        loc=loc,
        cond=cond,
        temp=temp,
        feels=feels,
        unit=unit,
        icon_map=icon_map,
        is_day=is_day,
        fallback_icon=fallback_icon,
        sunrise=sunrise,
        sunset=sunset,
        now_pop=now_pop,
        precip_amt=precip_amt,
        precip_unit=precip_unit,
    )

    astro_table = make_astro3d_table(three_hour_rows, astro_by_date or {})
    astro_header = f"<b>{style_icon(SUNRISE_ICON, COLOR_PRIMARY, ICON_SIZE_SM)} Week Sunrise / Sunset</b>"

    detail_header = (
        f"<b>{style_icon('󰨳', COLOR_PRIMARY, ICON_SIZE_SM)} Week Details</b>"
    )
    detail_table = make_3h_table(three_hour_rows, unit, precip_unit, icon_map)

    return (
        f"{header_block}\n"
        f"{astro_header}\n\n{astro_table}\n\n{divider()}\n\n"
        f"{detail_header}\n\n"
        f"{detail_table}"
    )


def build_text_and_tooltip(
    loc: Dict[str, Any],
    cond: str,
    temp: float,
    feels: float,
    precip_amt: float,
    is_day: int,
    next_hours: List[Dict[str, Any]],
    days: List[Dict[str, Any]],
    unit: str,
    precip_unit: str,
    icon_map: List[Dict[str, Any]],
    icon_pos: str,
    fallback_icon: str,
    sunrise: str,
    sunset: str,
) -> Tuple[str, str]:
    # icon for current condition
    cond_icon_raw = map_condition_icon(icon_map, cond, bool(is_day)) or fallback_icon

    # main text with waybar icon
    waybar_icon = style_icon(cond_icon_raw, COLOR_PRIMARY, ICON_SIZE_SM)
    left = f"{waybar_icon} {int(round(temp))}{unit}"
    right = f"{int(round(temp))}{unit} {waybar_icon}"
    text = left if (icon_pos or "left") == "left" else right

    # tables
    next_hours_table = make_hour_table(next_hours, unit, precip_unit, icon_map)
    next_days_overview_table = make_day_table(days, unit, precip_unit, icon_map)

    header_block = build_header_block(
        loc=loc,
        cond=cond,
        temp=temp,
        feels=feels,
        unit=unit,
        icon_map=icon_map,
        is_day=is_day,
        fallback_icon=fallback_icon,
        sunrise=sunrise,
        sunset=sunset,
        now_pop=int(next_hours[0]["pop"]) if next_hours else None,
        precip_amt=precip_amt,
        precip_unit=precip_unit,
    )

    tooltip = (
        f"{header_block}\n"
        f"<b>{style_icon('', COLOR_PRIMARY, ICON_SIZE_SM)} Next {len(next_hours)} hours</b>\n\n{next_hours_table}\n\n{divider()}\n\n"
        f"<b>{style_icon('󰨳', COLOR_PRIMARY, ICON_SIZE_SM)} Week Overview</b>\n\n{next_days_overview_table}"
    )

    return text, tooltip


# ─── Main runner ────────────────────────────────────────────────────────────
def main() -> None:
    # quick mode ops (no network)
    if len(sys.argv) > 1:
        a = sys.argv[1]
        if a in ("--next", "--toggle"):
            cycle_mode("next")
            return
        if a == "--prev":
            cycle_mode("prev")
            return
        if a == "--set" and len(sys.argv) > 2:
            set_mode(sys.argv[2])
            return

    script_path = os.path.dirname(os.path.realpath(__file__))

    try:
        cfg = load_config(script_path)
        mode = get_mode()
        unit_c: bool = safe(cfg, "unit", "Celsius") == "Celsius"
        hours_ahead: int = int(safe(cfg, "hours_ahead", 24) or 24)
        icon_pos: str = str(safe(cfg, "icon-position", "left") or "left")
        unit: str = "°C" if unit_c else "°F"
        precip_unit: str = "mm" if unit_c else "in"

        # data
        blob = fetch_weatherapi_forecast(str(cfg["key"]), str(cfg["parameters"]))
        astro_by_date = build_astro_by_date(blob)
        cur = extract_current(blob, unit_c)
        next_hours = build_next_hours(blob, unit_c, cur["now_local"], hours_ahead)
        days = build_next_days(blob, unit_c, 7)
        next_3days_detailed = build_next_3days_detailed(
            blob, unit_c, cur["now_local"], num_days=3
        )
        sunrise, sunset = get_sun_times(blob, cur["now_local"])

        # icons
        icon_map = load_icon_map(script_path)
        fallback_icon = (
            map_condition_icon(icon_map, cur["cond"], bool(cur["is_day"])) or ""
        )

        # Default tooltip (compact)
        text_default, tooltip_default = build_text_and_tooltip(
            loc=cur["loc"],
            cond=cur["cond"],
            temp=cur["temp"],
            feels=cur["feels"],
            precip_amt=cur["precip_amt"],
            is_day=cur["is_day"],
            next_hours=next_hours,
            days=days,
            unit=unit,
            precip_unit=precip_unit,
            icon_map=icon_map,
            icon_pos=icon_pos,
            fallback_icon=fallback_icon,
            sunrise=sunrise,
            sunset=sunset,
        )

        # Detail tooltip (3-hour view)
        tooltip_week_view = build_week_view_tooltip(
            loc=cur["loc"],
            cond=cur["cond"],
            temp=cur["temp"],
            feels=cur["feels"],
            unit=unit,
            icon_map=icon_map,
            is_day=cur["is_day"],
            fallback_icon=fallback_icon,
            three_hour_rows=next_3days_detailed,
            precip_unit=precip_unit,
            sunrise=sunrise,
            sunset=sunset,
            now_pop=int(next_hours[0]["pop"]) if next_hours else None,
            precip_amt=cur["precip_amt"],
            astro_by_date=astro_by_date,
        )

        text = text_default
        tooltip = tooltip_week_view if mode == "weekview" else tooltip_default

        classes = [
            "weather",
            "mode-weekview" if mode == "weekview" else "mode-default",
            "pop-high"
            if (next_hours and int(next_hours[0]["pop"]) >= 60)
            else "pop-low",
        ]

        out = {"text": text, "tooltip": tooltip, "alt": cur["cond"], "class": classes}

        # provider_note = (
        #     ""
        #     if len(days) >= 7
        #     else "\n\n<i>(Only 3 days returned by WeatherAPI free plan)</i>"
        # )

        out = {
            "text": text,
            "tooltip": tooltip,  # + provider_note
            "alt": cur["cond"],
            "class": [
                "weather",
                "pop-high"
                if (next_hours and int(next_hours[0]["pop"]) >= 60)
                else "pop-low",
            ],
        }
        print(json.dumps(out, ensure_ascii=False))

    except requests.RequestException:
        time.sleep(2)
        print(json.dumps({"text": "…", "tooltip": "network error; retrying"}))
    except (json.JSONDecodeError, KeyError, ValueError) as e:
        print(json.dumps({"text": "", "tooltip": f"parse error: {e}"}))


if __name__ == "__main__":
    main()
