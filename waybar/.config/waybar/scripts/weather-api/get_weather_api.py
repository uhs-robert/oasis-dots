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

import html
import json
import os
import time
from datetime import datetime
from typing import Any, Dict, List, Tuple

import requests

# ─── Constants ──────────────────────────────────────────────────────────────
ICON_COLOR: str = "#42A5F5"
ICON_COLOR_ALT: str = "#FB9D44"
ICON_SIZE: str = "14000"  # pango units; ~14pt
ICON_SIZE_LG: str = "18000"
ICON_SIZE_SM: str = "12000"
POP_ALERT_THRESHOLD: int = 60
POP_ICON_HIGH: str = ""
POP_ICON_LOW: str = ""
SUNRISE_ICON: str = ""
SUNSET_ICON: str = "󰖚"
HOUR_TABLE_HEADER_TEXT: str = (
    f"{'Hour':<4} │ {'Temp':>5} │ {'PoP':>3} │ {'Precip':>7} │ Cond"
)
DAY_TABLE_HEADER_TEXT: str = (
    f"{'Day':<9} │ {'Hi':>5} │ {'Lo':>5} │ {'PoP':>4} │ {'Precip':>8} │ Cond"
)


# ─── Utilities ──────────────────────────────────────────────────────────────
def safe(d: Dict[str, Any], k: str, default: Any = None) -> Any:
    return d[k] if k in d else default


def load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


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


def style_icon(glyph: str, color: str = ICON_COLOR, size: str = ICON_SIZE) -> str:
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


# ─── Tables & Tooltip ───────────────────────────────────────────────────────
def make_hour_table(next_hours, unit, precip_unit, icon_map) -> str:
    header = f"<span weight='bold'>{HOUR_TABLE_HEADER_TEXT}</span>"
    rows = []
    for h in next_hours:
        temp_col = f"{int(round(h['temp']))}{unit}".rjust(5)
        pop_col = f"{int(h['pop'])}%".rjust(3)
        precip_col = f"{h['precip']:.1f} {precip_unit}".rjust(7)
        glyph = map_condition_icon(icon_map, str(h["cond"]), bool(h.get("is_day", 1)))
        icon_html = style_icon(glyph, ICON_COLOR, ICON_SIZE_LG) if glyph else ""
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
        hi = int(round(d["max"]))
        lo = int(round(d["min"]))
        pop = max(0, min(100, int(d["pop"])))
        precip = float(d["precip"])
        cond_txt = str(d["cond"])
        glyph = map_condition_icon(icon_map, cond_txt, True)
        icon_html = style_icon(glyph, ICON_COLOR, ICON_SIZE_LG) if glyph else ""
        cond_cell = f"{icon_html} {html.escape(cond_txt)}".strip()
        row = (
            f"{fmt_dow(d['date']):<9} │ "
            f"{hi:>3}{unit} │ "
            f"{lo:>3}{unit} │ "
            f"{pop:>3}% │ "
            f"{precip:>5.1f} {precip_unit} │ "
            f"{cond_cell}"
        )
        out_rows.append(row)

    return (
        f"<span font_family='monospace'>{header}\n" + "\n".join(out_rows) + "</span>"
        if out_rows
        else "No daily data"
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
    cond_icon = style_icon(cond_icon_raw)

    # main text with big icon
    big_icon = style_icon(cond_icon_raw)
    left = f"{big_icon} {int(round(temp))}{unit}"
    right = f"{int(round(temp))}{unit} {big_icon}"
    text = left if (icon_pos or "left") == "left" else right

    # tables
    next_hours_table = make_hour_table(next_hours, unit, precip_unit, icon_map)
    days_table = make_day_table(days, unit, precip_unit, icon_map)

    # header lines (no bullets)
    location_line = (
        f"<b>{html.escape(str(loc.get('name', 'Local')))}, "
        f"{html.escape(str(loc.get('region', '')))} "
        f"{html.escape(str(loc.get('country', '')))}</b>"
    )
    current_line = f"{cond_icon} {html.escape(cond)} {int(round(temp))}{unit} (feels {int(round(feels))}{unit})"
    now_pop = int(next_hours[0]["pop"]) if next_hours else 0

    pop_icon_html = style_icon(icon_for_pop(now_pop))
    now_line = f"{pop_icon_html} PoP {now_pop}%, Precip {precip_amt:.1f}{precip_unit}"
    astro_line = ""
    if sunrise or sunset:
        astro_line = f"{style_icon(SUNRISE_ICON)} Sunrise {html.escape(sunrise or '—')} | {style_icon(SUNSET_ICON)} Sunset {html.escape(sunset or '—')}"

    tooltip = (
        f"{location_line}\n\n"
        f"{current_line}\n"
        f"{astro_line}\n{now_line}\n\n"
        f"<b>{style_icon('', ICON_COLOR, ICON_SIZE_SM)} Next {len(next_hours)} hours</b>\n\n{next_hours_table}\n\n"
        f"<b>{style_icon('󰨳', ICON_COLOR, ICON_SIZE_SM)} Next Few Days</b>\n\n{days_table}"
    )

    return text, tooltip


# ─── Main runner ────────────────────────────────────────────────────────────
def main() -> None:
    script_path = os.path.dirname(os.path.realpath(__file__))
    try:
        cfg = load_config(script_path)
        unit_c: bool = safe(cfg, "unit", "Celsius") == "Celsius"
        hours_ahead: int = int(safe(cfg, "hours_ahead", 12) or 12)
        icon_pos: str = str(safe(cfg, "icon-position", "left") or "left")
        unit: str = "°C" if unit_c else "°F"
        precip_unit: str = "mm" if unit_c else "in"

        # data
        blob = fetch_weatherapi_forecast(str(cfg["key"]), str(cfg["parameters"]))
        cur = extract_current(blob, unit_c)
        next_hours = build_next_hours(blob, unit_c, cur["now_local"], hours_ahead)
        days = build_next_days(blob, unit_c, 7)
        sunrise, sunset = get_sun_times(blob, cur["now_local"])

        # icons
        icon_map = load_icon_map(script_path)
        fallback_icon = (
            map_condition_icon(icon_map, cur["cond"], bool(cur["is_day"])) or ""
        )

        text, tooltip = build_text_and_tooltip(
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

        provider_note = (
            ""
            if len(days) >= 7
            else "\n\n<i>(Only 3 days returned by WeatherAPI free plan)</i>"
        )

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
