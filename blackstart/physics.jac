"""BLACKSTART - the clock. NO AI IN THIS FILE, BY DESIGN.

One tick is 15 simulated minutes. Every tick, in this fixed order:

    1. advance the simulation clock
    2. refresh solar output from the real hourly curve
    3. run the brain  (islanding -> endurance -> shedding)
    4. dispatch energy for the interval and move the physical state

Dispatch priority inside an island is always the same and is never a
judgement call: solar first (free), then the genset up to its power rating
(it is the only source with a large energy reserve behind it), then the
battery for the remainder. Surplus solar charges the battery. This is the
same ordering triage.project_endurance uses -- they have to agree or the
survival clock is a lie. See the note in triage.jac for why the intuitive
"battery before diesel" ordering strands the whole fuel tank.

A genset that runs out of fuel simply stops being an energised source --
islanding notices on the next cycle, so there is no special case anywhere
for "the generator died".
"""

import from grid { GridNode, GridTie, Solar, Battery, Genset, Load, Base }
import from triage { RunTriage, measure_island, assets_of }

glob DT_H: float = 0.25;               # 15 simulated minutes per tick


"""Deterministic ordering for dispatch -- alphabetical, never dict order."""
def by_name(n: GridNode) -> str {
    if isinstance(n, Battery) {
        return (n as Battery).name;
    }
    if isinstance(n, Genset) {
        return (n as Genset).name;
    }
    return "";
}


"""Live batteries in one island, in a stable order."""
def batteries_in(base: Base, island_id: int) -> list[Battery] {
    return sorted(
        [
            a as Battery for a in assets_of(base)
            if isinstance(a, Battery) and a.island_id == island_id and a.alive
        ],
        key=by_name
    );
}


"""Live gensets in one island, in a stable order."""
def gensets_in(base: Base, island_id: int) -> list[Genset] {
    return sorted(
        [
            a as Genset for a in assets_of(base)
            if isinstance(a, Genset) and a.island_id == island_id and a.alive
        ],
        key=by_name
    );
}


"""Push kWh into the island's batteries, respecting charge-rate limits.

Returns the energy actually absorbed. Anything left over is curtailed --
on a real site that is the inverter clipping, and it is not a bug.
"""
def charge_batteries(batts: list[Battery], kwh: float) -> float {
    remaining = kwh;
    absorbed = 0.0;
    for b in batts {
        if remaining <= 0.0 {
            break;
        }
        headroom = min(b.capacity_kwh - b.soc_kwh, b.max_charge_kw * DT_H);
        take = min(headroom, remaining);
        if take > 0.0 {
            b.soc_kwh += take;
            absorbed += take;
            remaining -= take;
        }
    }
    return absorbed;
}


"""Pull kWh out of the island's batteries. Returns what was actually served."""
def discharge_batteries(batts: list[Battery], kwh: float) -> float {
    remaining = kwh;
    served = 0.0;
    for b in batts {
        if remaining <= 0.0 {
            break;
        }
        available = min(b.soc_kwh, b.max_discharge_kw * DT_H);
        take = min(available, remaining);
        if take > 0.0 {
            b.soc_kwh -= take;
            served += take;
            remaining -= take;
        }
    }
    return served;
}


"""Run the gensets for this interval and burn the matching fuel.

Fuel burn is proportional to output, not to runtime: a generator loafing at
20% does not drink like one at full load.
"""
def run_gensets(gens: list[Genset], kwh: float) -> float {
    remaining = kwh;
    served = 0.0;
    for g in gens {
        g.output_kw = 0.0;
        if remaining <= 0.0 or g.fuel_liters <= 0.0 {
            continue;
        }
        fuel_limited_kwh = (g.fuel_liters / g.burn_lph) * g.rated_kw;
        available = min(g.rated_kw * DT_H, fuel_limited_kwh);
        take = min(available, remaining);
        if take > 0.0 {
            g.output_kw = take / DT_H;
            utilisation = g.output_kw / g.rated_kw;
            g.fuel_liters = max(0.0, g.fuel_liters - g.burn_lph * utilisation * DT_H);
            served += take;
            remaining -= take;
        }
    }
    return served;
}


"""Refresh every PV array from the cached hourly curve.

The curve was fetched once from real NREL PVWatts data and written onto the
graph. The tick loop reads only from the graph, so a network hiccup -- or a
dead conference wifi -- can never stall the simulation.
"""
def refresh_solar(base: Base) -> None {
    if len(base.solar_curve) != 24 {
        return;
    }
    idx = int(base.sim_hour) % 24;
    frac = max(0.0, base.solar_curve[idx] * base.solar_scale);
    for a in assets_of(base) {
        if isinstance(a, Solar) {
            s = a as Solar;
            s.output_kw = (s.capacity_kw * frac) if s.alive else 0.0;
        }
    }
}


"""Move one island's physical state forward by one tick.

Returns the unserved energy in kWh -- non-zero means a genuine brownout,
which only happens if even tier-1 load exceeds everything we can generate.
"""
def dispatch_island(base: Base, island_id: int) -> float {
    e = measure_island(base, island_id);
    batts = batteries_in(base, island_id);
    gens = gensets_in(base, island_id);
    demand_kwh = e.load_kw * DT_H;
    solar_kwh = e.solar_now_kw * DT_H;

    if e.grid_tie {
        # City power is up. It carries the load, and any spare solar plus
        # cheap grid energy tops the batteries off. When a storm is forecast
        # SURVEYOR raises storm_prep and we charge hard while we still can.
        surplus = max(0.0, solar_kwh - demand_kwh);
        if base.storm_prep {
            surplus = max(surplus, e.batt_max_kw * DT_H);
        }
        _ = charge_batteries(batts, surplus);
        for g in gens {
            g.output_kw = 0.0;
        }
        return 0.0;
    }

    # Islanded. Solar first, then the genset up to its rating, then the
    # battery for whatever is left. This ordering MUST match
    # triage.project_endurance -- see the long note there for why the
    # intuitive "battery before diesel" ordering is wrong.
    net_kwh = demand_kwh - solar_kwh;
    if net_kwh <= 0.0 {
        _ = charge_batteries(batts, -net_kwh);
        for g in gens {
            g.output_kw = 0.0;
        }
        return 0.0;
    }
    served = run_gensets(gens, net_kwh);
    served += discharge_batteries(batts, net_kwh - served);
    return max(0.0, net_kwh - served);
}


walker TickWalker {
    """One 15-minute step: clock -> solar -> brain -> physics."""

    has unserved_kwh: float = 0.0;
    has actions: list[str] = [];
    has reports: list[str] = [];

    can tick with Base entry {
        here.sim_hour = (here.sim_hour + DT_H) % 24.0;
        here.tick_count += 1;
        refresh_solar(here);

        # Decide first...
        brain = here spawn RunTriage();
        self.actions = brain.actions;

        # ...then act. Dispatch moves battery charge and burns fuel.
        for i in range(here.island_count) {
            self.unserved_kwh += dispatch_island(here, i);
        }

        # ...then measure again. Without this the survival clock on the Base
        # node is one dispatch step stale -- it would describe the grid as it
        # was before the batteries moved. Cheap at ~30 nodes, and it means the
        # number the operator reads is always current. Any extra shedding it
        # decides is a real decision and is logged like any other.
        after = here spawn RunTriage();
        self.actions += after.actions;
        # No `report` -- it echoes to stdout. Callers read `self.actions`.
    }
}
