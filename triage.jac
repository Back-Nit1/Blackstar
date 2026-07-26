"""BLACKSTART - the brain. NO AI IN THIS FILE, BY DESIGN.

Three steps, in this order, every cycle:
    1. islanding  -- who can still reach a working power source
    2. endurance  -- how long each island lasts, on the real solar forecast
    3. shedding   -- what we turn off so the mission survives 72 hours

The same situation must produce the same answer every single time. That is
what separates a grid controller from "an AI guesses what to turn off": a
judge can run the same action twice and get the same sequence, and an
operator can point at the rule that fired. So: no model calls, no randomness,
no wall-clock reads, and every ordering is total (tier, then priority, then
name -- alphabetical tiebreak).

If a `byllm` import ever appears in this file, that is a bug by definition.
"""

import from grid {
    GridNode, GridTie, Solar, Battery, Genset, Load, Base, Feeds, PartOf
}

# ── Policy constants ───────────────────────────────────────────────────
# 72 hours is a real resilience target: Japan sized its post-2011 community
# microgrids for ~3 days of autonomous operation. MARGIN is hysteresis --
# without it a load sitting right on the line flips on and off every tick as
# solar wiggles. Real energy-management systems use the same dead-band.
glob SURVIVAL_TARGET_H: float = 72.0;
glob RESTORE_MARGIN_H: float = 12.0;
glob HORIZON_H: int = 168;             # cap the projection at 7 days
glob EPSILON_KW: float = 0.001;        # never divide by zero


obj IslandEnergy {
    """A computed, read-only view of one electrical island."""

    has island_id: int = -1;
    has batt_kwh: float = 0.0;
    has batt_cap_kwh: float = 0.0;
    has batt_max_kw: float = 0.0;
    has fuel_kwh: float = 0.0;
    has genset_kw: float = 0.0;
    has solar_cap_kw: float = 0.0;
    has solar_now_kw: float = 0.0;
    has grid_tie: bool = False;
    has load_kw: float = 0.0;          # what is actually still energised
    has total_load_kw: float = 0.0;    # including everything we shed
    has survival_hours: float = 0.0;
    has load_names: list[str] = [];
    has shed_names: list[str] = [];
}


# ── 1. Islanding ───────────────────────────────────────────────────────
# Elsewhere this is "keep an adjacency list, hand-write a BFS, and keep it in
# sync with the database." Here the grid IS the adjacency list and the walker
# IS the BFS. The algorithm and the graph walk are the same object.

walker IslandWalker {
    """Walk outward from one energised source along live wires only."""

    has island_id: int;
    has reached: int = 0;

    can mark with GridNode entry {
        # A destroyed asset conducts nothing and is in no island.
        if not here.alive {
            skip;
        }
        # Already claimed by an earlier source -- same island, stop here.
        if here.island_id != -1 {
            skip;
        }
        # An open utility breaker is a hard electrical boundary. This is why
        # killing the city tie SPLITS the base instead of just removing a
        # source: the dead tie stops conducting between the feeders it fed.
        if isinstance(here, GridTie) and not (here as GridTie).live {
            skip;
        }
        here.island_id = self.island_id;
        self.reached += 1;
        # Power flows both ways down a feeder, so follow live edges in both
        # directions. A cut edge (live == False) is simply not in the result,
        # which is why islands appear with no special-case code anywhere.
        visit [here ->:Feeds:live == True:->];  # jac:ignore[W2075]
        visit [here <-:Feeds:live == True:<-];  # jac:ignore[W2075]
    }
}


"""Can this asset put energy on the wire right now?"""
def is_energised_source(n: GridNode) -> bool {
    if not n.alive {
        return False;
    }
    if isinstance(n, GridTie) {
        return (n as GridTie).live;
    }
    if isinstance(n, Battery) {
        return (n as Battery).soc_kwh > 0.0;
    }
    if isinstance(n, Genset) {
        return (n as Genset).fuel_liters > 0.0;
    }
    if isinstance(n, Solar) {
        return (n as Solar).output_kw > 0.0;
    }
    return False;
}


"""Total, stable ordering for source seeding -- keeps island ids stable."""
def source_rank(n: GridNode) -> str {
    if isinstance(n, GridTie) {
        return "0:" + (n as GridTie).utility;
    }
    if isinstance(n, Battery) {
        return "1:" + (n as Battery).name;
    }
    if isinstance(n, Genset) {
        return "2:" + (n as Genset).name;
    }
    if isinstance(n, Solar) {
        return "3:" + (n as Solar).name;
    }
    return "9:";
}


"""Every physical asset attached to this base."""
def assets_of(base: Base) -> list[GridNode] {
    return [base <-:PartOf:<-];
}


"""Clear every island tag, then re-seed a walker from each energised source.

Roughly 30 nodes, so we recompute from scratch every cycle. No caching, no
incremental updates -- simple is correct at this size.
"""
def recompute_islands(base: Base) -> int {
    assets = assets_of(base);
    for a in assets {
        a.island_id = -1;
    }
    sources = [a for a in assets if is_energised_source(a)];
    ordered = sorted(sources, key=source_rank);
    next_id = 0;
    for s in ordered {
        if s.island_id != -1 {
            continue;
        }
        _ = s spawn IslandWalker(island_id=next_id);
        next_id += 1;
    }
    return next_id;
}


# ── 2. The survival clock ──────────────────────────────────────────────

"""Forward-integrate the REAL hourly solar forecast until storage empties.

Deliberately NOT `stored / load`: that number is meaningless on a solar
microgrid, where the same island is comfortable at noon and starving at 2am.
We step the actual forecast curve hour by hour and report the hour the lights
go out.

Dispatch order inside each hour is fixed and matches physics.jac exactly --
if the projection and the simulation disagreed, the survival clock would be
a lie:

    1. solar          free, use every watt of it
    2. generator      up to its POWER rating, because it is the only source
                      with a large energy reserve behind it
    3. battery        covers whatever the generator's rating cannot, and
                      absorbs surplus solar during the day

The tempting order is "battery before generator, fuel is precious". It is
wrong, and it is wrong in a way that costs lives on stage: draining the
battery first strands the whole fuel tank behind the genset's kW rating, so
the moment the battery empties an island with load above genset rating is
declared dead while sitting on 120 MWh of diesel. You conserve fuel by
shedding load, not by idling the machine that carries the base load.
"""
def project_endurance(
    e: IslandEnergy,
    load_kw: float,
    curve: list[float],
    scale: float,
    start_hour: float
) -> float {
    if load_kw <= EPSILON_KW {
        return HORIZON_H as float;
    }
    if len(curve) != 24 {
        return 0.0;
    }
    b = e.batt_kwh;
    f = e.fuel_kwh;
    h = 0;
    while h < HORIZON_H {
        idx = int((start_hour + (h as float)) % 24.0);
        # One-hour step, so kW and kWh are numerically the same here.
        solar = max(0.0, e.solar_cap_kw * curve[idx] * scale);
        net = load_kw - solar;
        if net <= 0.0 {
            # Surplus solar recharges the battery. It never refills the tank.
            b = min(e.batt_cap_kwh, b - net);
        } else {
            from_fuel = min(min(f, net), e.genset_kw);
            from_batt = min(min(b, net - from_fuel), e.batt_max_kw);
            served = from_batt + from_fuel;
            if served < net {
                # We run dry partway through this hour.
                return (h as float) + served / net;
            }
            b -= from_batt;
            f -= from_fuel;
        }
        h += 1;
    }
    return HORIZON_H as float;
}


"""Add up one island's generation, storage and load straight off the graph."""
def measure_island(base: Base, island_id: int) -> IslandEnergy {
    e = IslandEnergy(island_id=island_id);
    for a in assets_of(base) {
        if a.island_id != island_id or not a.alive {
            continue;
        }
        if isinstance(a, Battery) {
            bt = a as Battery;
            e.batt_kwh += bt.soc_kwh;
            e.batt_cap_kwh += bt.capacity_kwh;
            e.batt_max_kw += bt.max_discharge_kw;
        } elif isinstance(a, Genset) {
            g = a as Genset;
            # liters -> kWh: hours of fuel at full power x rated output.
            if g.burn_lph > 0.0 {
                e.fuel_kwh += (g.fuel_liters / g.burn_lph) * g.rated_kw;
            }
            e.genset_kw += g.rated_kw;
        } elif isinstance(a, Solar) {
            s = a as Solar;
            e.solar_cap_kw += s.capacity_kw;
            e.solar_now_kw += s.output_kw;
        } elif isinstance(a, GridTie) {
            if (a as GridTie).live {
                e.grid_tie = True;
            }
        } elif isinstance(a, Load) {
            ld = a as Load;
            e.total_load_kw += ld.demand_kw;
            if ld.shed {
                e.shed_names.append(ld.name);
            } else {
                e.load_kw += ld.demand_kw;
                e.load_names.append(ld.name);
            }
        }
    }
    e.load_names = sorted(e.load_names);
    e.shed_names = sorted(e.shed_names);
    return e;
}


"""Survival hours for an island at a hypothetical load level."""
def endurance_of(base: Base, e: IslandEnergy, load_kw: float) -> float {
    if e.grid_tie {
        # City power is up: endurance is not the binding constraint.
        return HORIZON_H as float;
    }
    return project_endurance(
        e, load_kw, base.solar_curve, base.solar_scale, base.sim_hour
    );
}


# ── 3. Load shedding ───────────────────────────────────────────────────

"""Shed order: tier 3 first, then lowest priority, then alphabetical."""
def shed_key(l: Load) -> tuple[int, int, str] {
    return (-l.tier, l.priority, l.name);
}


"""Restore order: tier 2 back before tier 3, highest priority first."""
def restore_key(l: Load) -> tuple[int, int, str] {
    return (l.tier, -l.priority, l.name);
}


"""Shed the least-important load until the island clears 72 hours.

Tier 1 is never shed. If only tier 1 is left and we still miss the target we
report the honest lower number rather than touching the ICU, the radar or the
comms hut. Restores need MARGIN of headroom on top of the target, so nothing
flickers on and off as solar wiggles.
"""
def apply_shedding(base: Base, e: IslandEnergy) -> list[str] {
    actions: list[str] = [];
    loads = [
        a as Load for a in assets_of(base)
        if isinstance(a, Load) and a.island_id == e.island_id and a.alive
    ];
    live_load = e.load_kw;

    # --- shed down to the target -------------------------------------
    candidates = sorted(
        [l for l in loads if l.tier >= 2 and not l.shed], key=shed_key
    );
    for c in candidates {
        if endurance_of(base, e, live_load) >= SURVIVAL_TARGET_H {
            break;
        }
        c.shed = True;
        live_load -= c.demand_kw;
        actions.append(f"SHED tier-{c.tier} {c.name} (-{c.demand_kw:.0f} kW)");
    }

    # --- restore, but only with margin (hysteresis) -------------------
    shedable = sorted([l for l in loads if l.shed], key=restore_key);
    for c in shedable {
        trial = live_load + c.demand_kw;
        if endurance_of(base, e, trial) > SURVIVAL_TARGET_H + RESTORE_MARGIN_H {
            c.shed = False;
            live_load = trial;
            actions.append(f"RESTORE tier-{c.tier} {c.name} (+{c.demand_kw:.0f} kW)");
        } else {
            break;
        }
    }

    e.load_kw = live_load;
    e.load_names = sorted([l.name for l in loads if not l.shed]);
    e.shed_names = sorted([l.name for l in loads if l.shed]);
    e.survival_hours = endurance_of(base, e, live_load);
    return actions;
}


# ── The control loop ───────────────────────────────────────────────────

walker RunTriage {
    """islanding -> endurance -> shedding, in that order, with no AI."""

    has islands: list[IslandEnergy] = [];
    has actions: list[str] = [];
    has reports: list[IslandEnergy] = [];

    can run with Base entry {
        count = recompute_islands(here);
        for i in range(count) {
            e = measure_island(here, i);
            self.actions += apply_shedding(here, e);
            self.islands.append(e);
        }
        # The big number on screen: the weakest island decides the base.
        # A load in no island at all (island_id == -1) is simply dark.
        worst = HORIZON_H as float;
        for e in self.islands {
            if e.load_kw > 0.0 and e.survival_hours < worst {
                worst = e.survival_hours;
            }
        }
        here.survival_hours = worst;
        here.island_count = count;
        here.dark_loads = len([
            a for a in assets_of(here)
            if isinstance(a, Load) and a.island_id == -1
        ]);
        # Deliberately no `report` here. `report` echoes to stdout, and this
        # walker runs several times per tick. api.jac reports to the client.
    }
}
