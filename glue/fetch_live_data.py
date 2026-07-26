"""BLACKSTART glue - go fetch this from the internet. No logic lives here.

This script only does three things: call two free public APIs, pull the raw
fields out, and write them to data/live_feed.json. It makes no decisions and
holds no state. Every judgement about what a heat advisory means for the
grid is made in Jac (see agents.jac SURVEYOR), because the graph is the only
source of truth.

Run it whenever you want fresh data:  python glue/fetch_live_data.py
The simulation always reads the cached file, never the network, so a dead
conference wifi cannot stall a tick.
"""

import json
import pathlib
import urllib.request

LAT, LON = 33.79, -118.05  # JFTB Los Alamitos, CA
OUT = pathlib.Path(__file__).resolve().parent.parent / "data" / "live_feed.json"
UA = {"User-Agent": "BLACKSTART/0.1 (JacHacks SF demo)"}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def main():
    solar = get(
        "https://api.open-meteo.com/v1/forecast"
        f"?latitude={LAT}&longitude={LON}"
        "&hourly=shortwave_radiation,cloud_cover,temperature_2m"
        "&forecast_days=2&timezone=America%2FLos_Angeles"
    )
    alerts = get(f"https://api.weather.gov/alerts/active?point={LAT},{LON}")

    hourly = solar["hourly"]
    feats = alerts.get("features", [])
    props = feats[0]["properties"] if feats else {}

    OUT.write_text(json.dumps({
        "source_solar": "Open-Meteo forecast API (live, no key)",
        "source_alerts": "api.weather.gov active alerts (live, no key)",
        "fetched_for": hourly["time"][0],
        "ghi_wm2": hourly["shortwave_radiation"][:24],
        "cloud_pct": hourly["cloud_cover"][:24],
        "temp_c": hourly["temperature_2m"][:24],
        "alert_event": props.get("event", ""),
        "alert_severity": props.get("severity", ""),
        "alert_headline": props.get("headline", ""),
    }, indent=2))
    print(f"wrote {OUT} ({len(hourly['time'])} hours, alert={props.get('event') or 'none'})")


if __name__ == "__main__":
    main()
