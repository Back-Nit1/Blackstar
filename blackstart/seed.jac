"""BLACKSTART - build the Naval Medical Center Portsmouth twin.

WHAT IS REAL (public, citable):
  * NMCP occupies a 112-acre site on the Elizabeth River in downtown
    Portsmouth, Virginia.
  * Building 1 dates to 1830. Building 2 is the Charette Health Care Center,
    opened 30 April 1999, 1.02 million square feet. Building 3 opened in 1959.
  * Charette holds 353 inpatient beds, 17 operating rooms, 30 NICU and nursery
    beds, 300 exam rooms.
  * It is simultaneously a hospital and a DoD installation, which is why one
    demo satisfies both a CMS emergency-preparedness mandate and 10 U.S.C. 2925.

WHAT IS NOT REAL: the single-line diagram. No hospital publishes its electrical
drawings, and it would be irresponsible if one did. Substations, feeders, tie
switches and per-department kW are a labelled twin, sized from public building
data. The UI says so on screen.

THE NAMES ARE THE POINT. RED never sees a cable. It sees this roster, and
nothing else. "Riverside Substation", "Basement B2", "Pier-Side Fuel Farm" mean
something to anything that knows how weather and logistics work, and mean
nothing to a for-loop. We never encode elevation, flood risk or road access
anywhere in this graph -- if RED exploits them, it brought that knowledge.
"""

import from grid {
    GridNode, UtilityTie, Substation, Feeder, TieSwitch, Generator, Battery,
    SupplyRoute, Facility, Campus, Snapshot, Event, Decision, RedRound,
    Feeds, PartOf, Serves, Follows, Observed, Because, Triggered, Affected, Logged
}

glob PROVENANCE: str =
    "Facility roster, building numbers, bed and OR counts: real and public "
    "(Navy Medicine / NMCP). Single-line diagram: labelled twin -- no hospital "
    "publishes its electrical drawings.";


"""Attach a facility to a feeder and register it with the campus."""
def add_facility(
    campus: Campus, fdr: Feeder, name: str, building: str,
    kw: float, tier: int, priority: int
) -> Facility {
    f = Facility(
        name=name, building=building, demand_kw=kw, tier=tier, priority=priority
    );
    fdr +>:Feeds:+> f;
    f +>:PartOf:+> campus;
    return f;
}


"""Fill an empty Campus with the twin: sources, wiring, buildings.

Split out from campus creation on purpose -- see `rebuild_campus`. Everything
here hangs off the Campus node, never off `root`.
"""
def populate(campus: Campus) -> Campus {
    # ── the commercial feed ────────────────────────────────────────────
    tie = UtilityTie(utility="Dominion Energy Feed", capacity_kw=6000.0);
    tie +>:PartOf:+> campus;

    # ── two substations, deliberately asymmetric ───────────────────────
    # Riverside sits low, by the water, and carries the critical care tower.
    # Hilltop sits high and carries the support buildings -- and the big
    # generator. While the bus tie is closed nobody notices. Open it with the
    # utility down and the ICU is on the wrong side of the split.
    riverside = Substation(name="Riverside Substation", capacity_kw=3500.0);
    hilltop = Substation(name="Hilltop Substation", capacity_kw=3500.0);
    bus = TieSwitch(name="Campus Bus Tie");
    for n in [riverside, hilltop, bus] {
        n +>:PartOf:+> campus;
    }
    tie +>:Feeds:+> riverside;
    tie +>:Feeds:+> hilltop;
    riverside +>:Feeds:+> bus;
    bus +>:Feeds:+> hilltop;

    # ── feeders ────────────────────────────────────────────────────────
    f2a = Feeder(feeder_id="FDR-2A Charette Critical");
    f2b = Feeder(feeder_id="FDR-2B Charette Support");
    f13 = Feeder(feeder_id="FDR-13 Buildings 1 and 3");
    for n in [f2a, f2b] {
        riverside +>:Feeds:+> n;
        n +>:PartOf:+> campus;
    }
    hilltop +>:Feeds:+> f13;
    f13 +>:PartOf:+> campus;

    # ── generation and storage ─────────────────────────────────────────
    gen_base = Generator(
        name="Emergency Generator Plant - Basement B2",
        rated_kw=600.0, fuel_liters=800.0, bulk_liters=5200.0, burn_lph=160.0
    );
    gen_hill = Generator(
        name="Main Generator Plant - Hilltop",
        rated_kw=2000.0, fuel_liters=2500.0, bulk_liters=20000.0, burn_lph=500.0
    );
    ups_char = Battery(
        name="Central UPS - Charette", capacity_kwh=2000.0, soc_kwh=2000.0,
        max_discharge_kw=1200.0
    );
    ups_supp = Battery(
        name="Support UPS - Building 3", capacity_kwh=800.0, soc_kwh=800.0,
        max_discharge_kw=500.0
    );
    riverside +>:Feeds:+> gen_base;
    riverside +>:Feeds:+> ups_char;
    hilltop +>:Feeds:+> gen_hill;
    hilltop +>:Feeds:+> ups_supp;
    for n in [gen_base, gen_hill, ups_char, ups_supp] {
        n +>:PartOf:+> campus;
    }

    # ── the roads the fuel trucks use ──────────────────────────────────
    # These carry no power. Cut one and the generator it serves is down to its
    # day tank -- a few hours instead of a few days.
    route_hill = SupplyRoute(
        name="Gate 2 Fuel Delivery Route", serves="Main Generator Plant - Hilltop"
    );
    route_pier = SupplyRoute(
        name="Pier-Side Fuel Farm Access", serves="Emergency Generator Plant - Basement B2"
    );
    route_hill +>:Serves:+> gen_hill;
    route_pier +>:Serves:+> gen_base;
    for n in [route_hill, route_pier] {
        n +>:PartOf:+> campus;
    }

    # ── Building 2, Charette Health Care Center ────────────────────────
    # Tier 1 = NFPA 99 life-safety and critical branches. Never shed.
    _ = add_facility(campus, f2a, "Operating Rooms 1-17 - Charette", "Building 2", 320.0, 1, 98);
    _ = add_facility(campus, f2a, "Emergency Department - Charette", "Building 2", 200.0, 1, 96);
    _ = add_facility(campus, f2a, "ICU - Charette 4th Floor", "Building 2", 180.0, 1, 95);
    _ = add_facility(campus, f2a, "NICU - Charette", "Building 2", 120.0, 1, 97);
    _ = add_facility(campus, f2a, "Medical Gas and Vacuum Plant", "Building 2", 90.0, 1, 94);
    _ = add_facility(campus, f2a, "Blood Bank and Lab Refrigeration", "Building 2", 70.0, 1, 93);

    # Tier 2 = equipment branch. Shed only when desperate.
    _ = add_facility(campus, f2b, "Inpatient Wards 5-8 - Charette", "Building 2", 260.0, 2, 70);
    _ = add_facility(campus, f2b, "Pharmacy", "Building 2", 60.0, 2, 68);
    _ = add_facility(campus, f2b, "Clinical Laboratory", "Building 2", 120.0, 2, 65);
    _ = add_facility(campus, f2b, "Radiology and CT - Charette", "Building 2", 160.0, 2, 60);
    _ = add_facility(campus, f2b, "MRI Suite - Charette", "Building 2", 140.0, 2, 55);
    _ = add_facility(campus, f2b, "Basement Chiller Plant", "Building 2", 300.0, 2, 50);

    # Tier 3 = normal power. Sheds first.
    _ = add_facility(campus, f2b, "Cafeteria - Charette", "Building 2", 90.0, 3, 10);
    _ = add_facility(campus, f2b, "Staff Fitness Center", "Building 2", 40.0, 3, 8);
    _ = add_facility(campus, f2b, "Gift Shop and Retail", "Building 2", 25.0, 3, 5);

    # ── Buildings 1 and 3 ──────────────────────────────────────────────
    _ = add_facility(campus, f13, "Central Sterile Processing - Building 3", "Building 3", 110.0, 1, 92);
    _ = add_facility(campus, f13, "River Water Pump House", "Building 3", 80.0, 1, 91);
    _ = add_facility(campus, f13, "Ambulatory Surgery Center - Building 3", "Building 3", 150.0, 2, 58);
    _ = add_facility(campus, f13, "Sterile Supply Warehouse", "Building 3", 70.0, 2, 52);
    _ = add_facility(campus, f13, "Administration - Building 1 (1830)", "Building 1", 90.0, 2, 45);
    _ = add_facility(campus, f13, "Auditorium - Building 3", "Building 3", 45.0, 3, 6);
    _ = add_facility(campus, f13, "Exterior and Parking Lighting", "Campus", 60.0, 3, 4);
    _ = add_facility(campus, f13, "Chapel - Building 3", "Building 3", 20.0, 3, 12);
    _ = add_facility(campus, f13, "Grounds and Landscaping Shop", "Campus", 20.0, 3, 2);

    return campus;
}


"""Create the Campus node and attach it to root. Called at most ONCE.

`root` is the persistence anchor for the whole program. Every write to it
bumps a version the runtime checks at commit time, and repeatedly attaching
and deleting its children desynchronises that version -- you get
`WriteConflict: anchor 00000000-... changed concurrently` at process exit,
after the run has already printed correct results. So: touch root once, and
rebuild everything BELOW the Campus instead.
"""
def new_campus() -> Campus {
    campus = Campus(
        name="Naval Medical Center Portsmouth",
        lat=36.8354, lon=-76.3044,
        target_hours=96.0,
        provenance=PROVENANCE
    );
    root ++> campus;
    return populate(campus);
}


"""The campus on the graph, if one has been built."""
def find_campus() -> Campus | None {
    found = [root --> [?:Campus]];
    return found[0] if found else None;
}


"""Return the existing twin, or build one. Safe to call on every request."""
def ensure_campus() -> Campus {
    existing = find_campus();
    if existing is not None {
        return existing;
    }
    return new_campus();
}


"""Reset to a pristine twin. The demo reset button, and the A/B control.

Deletes everything hanging off the Campus -- assets, wiring, snapshots,
decisions, RED's memory -- then repopulates. The Campus node itself and its
single edge from `root` are never touched, which is what keeps the runtime's
root anchor at one stable version no matter how many times you reset.
"""
def rebuild_campus() -> Campus {
    existing = find_campus();
    if existing is None {
        return new_campus();
    }
    campus = existing as Campus;
    for a in [campus <-:PartOf:<-] {
        del a;
    }
    campus.tick = 0;
    campus.hours_left = 0.0;
    campus.island_count = 0;
    campus.dark_facilities = 0;
    campus.dark_tier1 = 0;
    campus.generation_kw = 0.0;
    campus.lit_load_kw = 0.0;
    campus.island_id = -1;
    campus.alive = True;
    return populate(campus);
}
