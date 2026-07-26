"""BLACKSTART - build the digital twin.

WHAT IS REAL AND WHAT IS NOT (this matters; overclaiming is disqualifying):

  * The grid LAYOUT is a labelled digital twin. A real installation's internal
    single-line diagram is not public, for obvious reasons. Feeder topology,
    building names and per-building demand are ours, sized from public DOE
    commercial-building energy profiles.
  * The generation MIX is modelled on published figures for JFTB Los Alamitos
    (~31 MW of on-site solar, tens of MWh of battery, MW-scale diesel).
  * The WEATHER and the SOLAR CURVE are real live public data, fetched from
    api.weather.gov and the Open-Meteo forecast API at the coordinates below.

One deliberate piece of engineering realism: the 31 MW utility-scale PV plant
sits on the UTILITY side of the point of common coupling. When the city tie
opens it drops out with the grid -- it is not islandable. Only the smaller
behind-the-meter arrays stay with the base. That is why losing the city tie
hurts far more than "we still have 31 MW of panels" suggests, and it is the
single most common misconception about military microgrids.
"""

import json;
import os;

import from grid {
    GridNode, GridTie, Solar, Battery, Genset, Feeder, Load, Base,
    IncidentLog, Feeds, PartOf
}

glob FEED_PATH: str = "data/live_feed.json";

# Standard test conditions are 1000 W/m^2. 0.86 is a conventional DC->AC,
# soiling and wiring derate (PVWatts default system losses are ~14%).
glob STC_WM2: float = 1000.0;
glob PV_DERATE: float = 0.86;

# A clear-July fallback curve for Los Alamitos, used only if the cached live
# feed is missing. Every demo step has an offline backup.
glob FALLBACK_CURVE: list[float] = [
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.02, 0.10,
    0.26, 0.44, 0.60, 0.72, 0.78, 0.77, 0.70, 0.57,
    0.41, 0.24, 0.09, 0.01, 0.0, 0.0, 0.0, 0.0
];


"""Irradiance (W/m^2) -> fraction of PV nameplate actually delivered."""
def solar_fraction(ghi_wm2: float) -> float {
    return min(1.0, max(0.0, ghi_wm2) / STC_WM2 * PV_DERATE);
}


"""Read the cached live feed off disk. Never called from the tick loop."""
def read_live_feed() -> dict[str, any] {
    try {
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), FEED_PATH);
        with open(path) as fh {
            return json.load(fh) as dict[str, any];
        }
    } except Exception {
        return {};
    }
}


"""Copy the live feed onto the graph. After this the graph is self-sufficient:
the tick loop reads solar and weather from Base, never from the network.
"""
def apply_live_feed(base: Base) {
    feed = read_live_feed();
    ghi: list[any] = (feed.get("ghi_wm2", []) as list[any]) if feed else [];
    if len(ghi) == 24 {
        base.solar_curve = [solar_fraction(v as float) for v in ghi];
        base.data_provenance = (
            "solar: " + (feed.get("source_solar", "") as str)
            + " | alerts: " + (feed.get("source_alerts", "") as str)
            + " | for " + (feed.get("fetched_for", "") as str)
        );
    } else {
        base.solar_curve = FALLBACK_CURVE;
        base.data_provenance = "OFFLINE CACHE - modelled clear-sky July curve";
    }
    event = (feed.get("alert_event", "") as str) if feed else "";
    headline = (feed.get("alert_headline", "") as str) if feed else "";
    base.weather_alert = len(event) > 0;
    base.weather_headline = headline if len(headline) > 0 else "No active NWS alert";
}


"""Wire a building onto a feeder and register it with the base."""
def add_load(
    base: Base, feeder: Feeder, name: str, kw: float, tier: int, priority: int
) -> Load {
    l = Load(name=name, demand_kw=kw, tier=tier, priority=priority);
    feeder +>:Feeds:+> l;
    l +>:PartOf:+> base;
    return l;
}


"""Build the whole twin from scratch and hang it off root."""
def build_twin() -> Base {
    base = Base(
        name="JFTB Los Alamitos (digital twin)", lat=33.79, lon=-118.05,
        sim_hour=18.0
    );
    root ++> base;
    root ++> IncidentLog();

    # ── the city connection ────────────────────────────────────────────
    tie = GridTie(utility="Southern California Edison", capacity_kw=20000.0);
    tie +>:PartOf:+> base;

    # Utility-scale PV, on the GRID side of the tie. Islanding drops it.
    pv_util = Solar(name="PV Utility Export Array", capacity_kw=31000.0);
    pv_util +>:Feeds:+> tie;
    pv_util +>:PartOf:+> base;

    # ── three feeders, on purpose ──────────────────────────────────────
    # Killing one line then causes a PARTIAL blackout, which demonstrates
    # islanding far better than an all-or-nothing base.
    fa = Feeder(feeder_id="FDR-A Mission");
    fb = Feeder(feeder_id="FDR-B Flightline");
    fc = Feeder(feeder_id="FDR-C Support");
    for f in [fa, fb, fc] {
        tie +>:Feeds:+> f;
        f +>:PartOf:+> base;
    }
    # Normally-closed bus tie: A and B ride through together.
    fa +>:Feeds:+> fb;

    # ── behind-the-meter generation (this is what actually islands) ────
    pv_a = Solar(name="PV Array A (carport)", capacity_kw=1800.0);
    pv_b = Solar(name="PV Array B (hangar roof)", capacity_kw=1000.0);
    bess1 = Battery(
        name="BESS-1", capacity_kwh=20000.0, soc_kwh=10000.0,
        max_discharge_kw=5000.0, max_charge_kw=4000.0
    );
    bess2 = Battery(
        name="BESS-2", capacity_kwh=10000.0, soc_kwh=5000.0,
        max_discharge_kw=2500.0, max_charge_kw=2000.0
    );
    # 0.25 L per kWh is a standard large-diesel heat rate.
    gen1 = Genset(
        name="GEN-1 Prime", rated_kw=2000.0, fuel_liters=30000.0, burn_lph=500.0
    );
    gen2 = Genset(
        name="GEN-2 Support", rated_kw=1000.0, fuel_liters=12000.0, burn_lph=250.0
    );
    fa +>:Feeds:+> pv_a;
    fa +>:Feeds:+> bess1;
    fa +>:Feeds:+> gen1;
    fb +>:Feeds:+> pv_b;
    fb +>:Feeds:+> bess2;
    fc +>:Feeds:+> gen2;
    for a in [pv_a, pv_b, bess1, bess2, gen1, gen2] {
        a +>:PartOf:+> base;
    }

    # ── the buildings ──────────────────────────────────────────────────
    # tier 1 = never shed, tier 2 = shed if desperate, tier 3 = shed first.
    # The 3-tier split is a direct copy of the NFPA 99 hospital branch model
    # (life safety / critical / equipment), so a facilities engineer reads it
    # without a translation layer. Lower `priority` sheds earlier.
    _ = add_load(base, fa, "Base Medical Clinic",     420.0, 1, 90);
    _ = add_load(base, fa, "Comms & Network Ops",     260.0, 1, 95);
    _ = add_load(base, fa, "Ops & Admin HQ",          340.0, 2, 60);
    _ = add_load(base, fa, "Fitness Center",          180.0, 3, 10);
    _ = add_load(base, fa, "Barracks A HVAC",         300.0, 3, 30);

    _ = add_load(base, fb, "Radar & ATC Tower",       380.0, 1, 99);
    _ = add_load(base, fb, "Water & Wastewater",      210.0, 1, 92);
    _ = add_load(base, fb, "Aircraft Hangar 1",       300.0, 2, 55);
    _ = add_load(base, fb, "Fuel Farm Pumps",         160.0, 2, 70);
    _ = add_load(base, fb, "Barracks B HVAC",         260.0, 3, 30);
    _ = add_load(base, fb, "Exterior Lighting",        90.0, 3, 20);

    _ = add_load(base, fc, "Emergency Dispatch",      150.0, 1, 98);
    _ = add_load(base, fc, "Vehicle Maintenance",     230.0, 2, 50);
    _ = add_load(base, fc, "Dining Facility",         180.0, 2, 65);
    _ = add_load(base, fc, "Motor Pool Wash Rack",     70.0, 3, 15);
    _ = add_load(base, fc, "Sports Field Lighting",    70.0, 3, 10);

    apply_live_feed(base);
    return base;
}


"""The base on the graph, if one has been built."""
def find_base() -> Base | None {
    found = [root --> [?:Base]];
    return found[0] if found else None;
}


"""The incident log on the graph, creating it if this is a fresh graph."""
def find_log() -> IncidentLog {
    found = [root --> [?:IncidentLog]];
    if found {
        return found[0];
    }
    return (root ++> IncidentLog())[0];
}


"""Return the existing twin, or build one. Safe to call on every start."""
def ensure_base() -> Base {
    existing = find_base();
    if existing is not None {
        return existing;
    }
    return build_twin();
}


"""Tear the whole graph down and rebuild it. This is the demo reset button."""
def rebuild_twin() -> Base {
    for n in [root --> ] {
        del n;
    }
    return build_twin();
}
