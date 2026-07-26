"""BLACKSTART - the clock. NO AI IN THIS FILE, BY DESIGN.

One tick is 15 simulated minutes and does exactly this, in this order:

    1. advance the clock and move the physical state (battery, fuel)
    2. island and measure -- WITHOUT acting
    3. write a Snapshot: this is the evidence
    4. record whatever caused this tick (a cut, a RED strike)
    5. let BLUE decide, and hang every decision off that Snapshot
    6. re-measure so the number on screen is current

Steps 2-5 are in that order because the audit chain has to record the state
that CAUSED a decision, not the state that resulted from it. Get this backwards
and "why did the cafeteria go dark" answers with the wrong numbers.

Dispatch inside an island is fixed and is never a judgement call: the generator
carries base load up to its rating, the battery covers what the rating cannot.
The tempting order -- battery first, fuel is precious -- strands the whole fuel
tank behind the generator's kW rating.
"""

import from grid {
    GridNode, UtilityTie, Generator, Battery, Facility, Campus,
    Snapshot, Event, Feeds, PartOf
}
import from triage {
    RunTriage, IslandState, ShedRecord, assets_of, refresh_state, blue_shed,
    measure_island, resupply_open
}
import from ops { record_snapshot, record_event, record_decision, asset_label }

glob DT_H: float = 0.25;            # 15 simulated minutes


"""Live generators in one island, in a stable order."""
def generators_in(campus: Campus, island_id: int) -> list[Generator] {
    return sorted(
        [
            a as Generator for a in assets_of(campus)
            if isinstance(a, Generator) and a.island_id == island_id and a.alive
        ],
        key=lambda g: Generator : g.name
    );
}


"""Live batteries in one island, in a stable order."""
def batteries_in(campus: Campus, island_id: int) -> list[Battery] {
    return sorted(
        [
            a as Battery for a in assets_of(campus)
            if isinstance(a, Battery) and a.island_id == island_id and a.alive
        ],
        key=lambda b: Battery : b.name
    );
}


"""Run the generators for this interval and burn the matching fuel.

Fuel comes out of the day tank first; the day tank tops up from bulk only when
the supply route is open. Cut the road and the machine runs out in hours.
"""
def run_generators(gens: list[Generator], kwh: float) -> float {
    remaining = kwh;
    served = 0.0;
    for g in gens {
        g.output_kw = 0.0;
        if remaining <= 0.0 {
            continue;
        }
        if resupply_open(g) and g.fuel_liters < g.burn_lph * DT_H * 4.0 {
            top_up = min(g.bulk_liters, g.burn_lph * DT_H * 8.0);
            g.fuel_liters += top_up;
            g.bulk_liters -= top_up;
        }
        if g.fuel_liters <= 0.0 {
            continue;
        }
        fuel_limited_kwh = (g.fuel_liters / g.burn_lph) * g.rated_kw;
        take = min(min(g.rated_kw * DT_H, fuel_limited_kwh), remaining);
        if take > 0.0 {
            g.output_kw = take / DT_H;
            g.fuel_liters = max(
                0.0, g.fuel_liters - g.burn_lph * (g.output_kw / g.rated_kw) * DT_H
            );
            served += take;
            remaining -= take;
        }
    }
    return served;
}


"""Pull kWh out of the island's batteries."""
def discharge_batteries(batts: list[Battery], kwh: float) -> float {
    remaining = kwh;
    served = 0.0;
    for b in batts {
        if remaining <= 0.0 {
            break;
        }
        take = min(min(b.soc_kwh, b.max_discharge_kw * DT_H), remaining);
        if take > 0.0 {
            b.soc_kwh -= take;
            served += take;
            remaining -= take;
        }
    }
    return served;
}


"""Push kWh into the island's batteries."""
def charge_batteries(batts: list[Battery], kwh: float) -> float {
    remaining = kwh;
    absorbed = 0.0;
    for b in batts {
        if remaining <= 0.0 {
            break;
        }
        take = min(min(b.capacity_kwh - b.soc_kwh, b.max_discharge_kw * DT_H), remaining);
        if take > 0.0 {
            b.soc_kwh += take;
            absorbed += take;
            remaining -= take;
        }
    }
    return absorbed;
}


"""Move one island's physical state forward. Returns unserved kWh."""
def dispatch_island(campus: Campus, island_id: int) -> float {
    st = measure_island(campus, island_id);
    gens = generators_in(campus, island_id);
    batts = batteries_in(campus, island_id);
    demand_kwh = st.draw_kw * DT_H;

    if st.has_utility {
        # Commercial power carries the load and tops the batteries off.
        _ = charge_batteries(batts, st.generation_kw * DT_H);
        for g in gens {
            g.output_kw = 0.0;
        }
        return 0.0;
    }
    served = run_generators(gens, demand_kwh);
    served += discharge_batteries(batts, demand_kwh - served);
    return max(0.0, demand_kwh - served);
}


"""Find a facility by name, for linking a decision to who it happened to."""
def facility_named(campus: Campus, name: str) -> list[Facility] {
    return [
        a as Facility for a in assets_of(campus)
        if isinstance(a, Facility) and (a as Facility).name == name
    ];
}


walker TickWalker {
    """One audited step of the world."""

    # what caused this tick, if anything -- recorded as the Event that
    # triggered whatever BLUE decides below
    has cause_kind: str = "";
    has cause_target: str = "";
    has cause_detail: str = "";
    has cause_actor: str = "operator";

    has actions: list[str] = [];
    has unserved_kwh: float = 0.0;

    can tick with Campus entry {
        here.tick += 1;

        # 1. move the physical state forward from the last dispatch
        for i in range(max(here.island_count, 0)) {
            self.unserved_kwh += dispatch_island(here, i);
        }

        # 2. island and measure, WITHOUT acting -- this is the evidence
        pre = refresh_state(here);

        # 3-4. write the snapshot and what caused this tick
        snap = record_snapshot(here);
        causes: list[Event] = [];
        if self.cause_kind {
            causes.append(record_event(
                here, snap, self.cause_kind, self.cause_target,
                self.cause_detail, self.cause_actor
            ));
        }
        # A generator that has run dry is worth recording even though the
        # islanding walker handles it with no special case.
        for a in assets_of(here) {
            if isinstance(a, Generator) {
                g = a as Generator;
                if g.alive and g.fuel_liters + g.bulk_liters <= 0.0 {
                    causes.append(record_event(
                        here, snap, "fuel_out", g.name,
                        "day tank and bulk both empty", "physics"
                    ));
                }
            }
        }
        cause = causes[0] if causes else None;

        # 5. BLUE decides, and every decision cites the snapshot above
        for st in pre {
            for rec in blue_shed(here, st) {
                subj = facility_named(here, rec.subject);
                _ = record_decision(
                    here, snap, cause, rec, subj[0] if subj else None
                );
                self.actions.append(
                    f"{rec.action} tier-{rec.tier} {rec.subject} "
                    f"({rec.hours_before:.1f}h -> {rec.hours_after:.1f}h)"
                );
            }
        }

        # 6. re-measure so the number on screen is current.
        # The Snapshot is deliberately NOT updated here. It is the evidence:
        # the state that caused the decisions above, not the state that
        # resulted from them. Overwrite it and "why did the cafeteria go dark"
        # answers with the number BLUE produced instead of the one it reacted
        # to, which is worse than useless.
        _ = refresh_state(here);
    }
}
