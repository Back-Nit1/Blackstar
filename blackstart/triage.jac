"""BLACKSTART - BLUE. The defense. NO AI IN THIS FILE, BY DESIGN.

Three steps, every tick, in this order:
    1. islanding  -- which facilities can still reach a working source
    2. endurance  -- hours of power left, per island
    3. shedding   -- turn off the least important thing until we clear target

BLUE is a checklist and a while loop, on purpose. Nobody is going to accredit a
language model to decide who loses power in a hospital. Predictability is the
point: run the same failure twice and you get the same answer twice, and an
engineer can point at the line that fired.

If a `byllm` import ever appears in this file, that is a bug by definition, and
there is a test that fails the build over it.

Once this file works, close it. The intelligence goes on the threat (agents.jac),
not here.
"""

import from grid {
    GridNode, UtilityTie, Substation, Feeder, TieSwitch, Generator, Battery,
    SupplyRoute, Facility, Campus, Feeds, PartOf, Serves
}

# 96 hours is the planning target. MARGIN is hysteresis -- without it a load
# sitting exactly on the line flips on and off every tick. Real energy
# management systems use the same dead-band.
glob TARGET_H: float = 96.0;
glob RESTORE_MARGIN_H: float = 12.0;
glob HORIZON_H: float = 240.0;      # cap the number; "10+ days" reads as fine
glob EPSILON_KW: float = 0.001;     # never divide by zero
# Diesel converts to energy at rated: fuel_liters / burn_lph * rated_kw.


obj IslandState {
    """A read-only view of one electrical island."""

    has island_id: int = -1;
    has stored_kwh: float = 0.0;
    has draw_kw: float = 0.0;           # what is still energised
    has total_load_kw: float = 0.0;     # including everything shed
    has generation_kw: float = 0.0;     # dispatchable capacity present
    has hours_left: float = 0.0;
    has has_utility: bool = False;
    has lit: list[str] = [];
    has shed_names: list[str] = [];
}


obj ShedRecord {
    """One BLUE decision, ready to be written into the audit chain."""

    has action: str = "";
    has subject: str = "";
    has tier: int = 0;
    has demand_kw: float = 0.0;
    has rule: str = "";
    has rationale: str = "";
    has hours_before: float = 0.0;
    has hours_after: float = 0.0;
}


# ── 1. Islanding ───────────────────────────────────────────────────────
# We never wrote a splitting algorithm. The walker only walks live cables, so
# a cut cable is simply absent from the query result and the islands fall out.
# Elsewhere this is "maintain an adjacency list, hand-write a BFS, keep it in
# sync with the database". Here the map IS the adjacency list and the walker
# IS the BFS.

walker IslandWalker {
    """Walk outward from one working source along live cables only."""

    has island_id: int = 0;
    has reached: int = 0;

    can mark with GridNode entry {
        if not here.alive {
            skip;                     # a dead asset conducts nothing
        }
        if here.island_id != -1 {
            skip;                     # already claimed by an earlier source
        }
        # An open main breaker is a hard electrical boundary. This is why
        # cutting the utility feed SPLITS the campus instead of just removing
        # a source.
        if isinstance(here, UtilityTie) and not (here as UtilityTie).live {
            skip;
        }
        here.island_id = self.island_id;
        self.reached += 1;
        visit [here ->:Feeds:live == True:->];   # jac:ignore[W2075]
        visit [here <-:Feeds:live == True:<-];   # jac:ignore[W2075]
    }
}


"""Every physical asset on the campus."""
def assets_of(campus: Campus) -> list[GridNode] {
    return [campus <-:PartOf:<-];
}


"""Can this asset put energy on the wire right now?"""
def is_source(n: GridNode) -> bool {
    if not n.alive {
        return False;
    }
    if isinstance(n, UtilityTie) {
        return (n as UtilityTie).live;
    }
    if isinstance(n, Battery) {
        return (n as Battery).soc_kwh > 0.0;
    }
    if isinstance(n, Generator) {
        gn = n as Generator;
        return gn.fuel_liters + gn.bulk_liters > 0.0;
    }
    return False;
}


"""Is the bulk fuel tank reachable? The truck needs an open road.

This is the whole flood -> road -> truck -> dry generator chain, made
mechanical. Cut the route and the machine is down to its day tank.
"""
def resupply_open(g: Generator) -> bool {
    routes = [g <-:Serves:<-];
    if not routes {
        return True;                 # no route modelled: bulk is on-site
    }
    for r in routes {
        if r.alive {
            return True;
        }
    }
    return False;
}


"""Stable seeding order so island ids do not shuffle between runs."""
def source_rank(n: GridNode) -> str {
    if isinstance(n, UtilityTie) {
        return "0:" + (n as UtilityTie).utility;
    }
    if isinstance(n, Generator) {
        return "1:" + (n as Generator).name;
    }
    if isinstance(n, Battery) {
        return "2:" + (n as Battery).name;
    }
    return "9:";
}


"""Clear every island tag, then re-seed a walker from each working source.

About 30 nodes, so we recompute from scratch every tick. No caching, no
incremental invalidation, no bugs.
"""
def recompute_islands(campus: Campus) -> int {
    assets = assets_of(campus);
    for a in assets {
        a.island_id = -1;
    }
    ordered = sorted([a for a in assets if is_source(a)], key=source_rank);
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


# ── 2. Hours left ──────────────────────────────────────────────────────
# Deliberately the simplest thing that is true: stored energy over what we are
# drawing. It has to be legible on a screen and walk-backable in the audit
# chain -- "generation fell 400 to 180 kW, hours left fell to 41".

"""Hours of power left for an island at a hypothetical draw."""
def hours_at(st: IslandState, draw_kw: float) -> float {
    if st.has_utility {
        return HORIZON_H;            # commercial power is up; not the constraint
    }
    if draw_kw <= EPSILON_KW {
        return HORIZON_H;
    }
    return min(HORIZON_H, st.stored_kwh / draw_kw);
}


"""Add up one island's storage, generation and load straight off the graph."""
def measure_island(campus: Campus, island_id: int) -> IslandState {
    st = IslandState(island_id=island_id);
    for a in assets_of(campus) {
        if a.island_id != island_id or not a.alive {
            continue;
        }
        if isinstance(a, Battery) {
            st.stored_kwh += (a as Battery).soc_kwh;
        } elif isinstance(a, Generator) {
            g = a as Generator;
            usable = g.fuel_liters;
            if resupply_open(g) {
                usable += g.bulk_liters;
            }
            if g.burn_lph > 0.0 {
                st.stored_kwh += (usable / g.burn_lph) * g.rated_kw;
            }
            st.generation_kw += g.rated_kw;
        } elif isinstance(a, UtilityTie) {
            ut = a as UtilityTie;
            if ut.live {
                st.has_utility = True;
                st.generation_kw += ut.capacity_kw;
            }
        } elif isinstance(a, Facility) {
            f = a as Facility;
            st.total_load_kw += f.demand_kw;
            if f.shed {
                st.shed_names.append(f.name);
            } else {
                st.draw_kw += f.demand_kw;
                st.lit.append(f.name);
            }
        }
    }
    st.lit = sorted(st.lit);
    st.shed_names = sorted(st.shed_names);
    st.hours_left = hours_at(st, st.draw_kw);
    return st;
}


# ── 3. BLUE ────────────────────────────────────────────────────────────

"""Shed order: tier 3 first, then lowest priority, then alphabetical."""
def shed_key(f: Facility) -> tuple[int, int, str] {
    return (-f.tier, f.priority, f.name);
}


"""Restore order: tier 2 comes back before tier 3, highest priority first."""
def restore_key(f: Facility) -> tuple[int, int, str] {
    return (f.tier, -f.priority, f.name);
}


"""The whole defense. Shed the least important thing until we clear target.

Tier 1 is never a candidate. If only tier 1 is left and we still miss target,
report the honest lower number rather than touching the ICU. Restores need
MARGIN of headroom on top of target so nothing flickers.
"""
def blue_shed(campus: Campus, st: IslandState) -> list[ShedRecord] {
    out: list[ShedRecord] = [];
    loads = [
        a as Facility for a in assets_of(campus)
        if isinstance(a, Facility) and a.island_id == st.island_id and a.alive
    ];
    draw = st.draw_kw;

    for c in sorted([f for f in loads if f.tier >= 2 and not f.shed], key=shed_key) {
        before = hours_at(st, draw);
        if before >= campus.target_hours {
            break;
        }
        c.shed = True;
        draw -= c.demand_kw;
        out.append(ShedRecord(
            action="SHED", subject=c.name, tier=c.tier, demand_kw=c.demand_kw,
            rule=f"hours_left < target ({campus.target_hours:.0f} h) -> shed lowest tier",
            rationale=f"{c.name} is tier {c.tier}; shedding it frees {c.demand_kw:.0f} kW",
            hours_before=before, hours_after=hours_at(st, draw)
        ));
    }

    for c in sorted([f for f in loads if f.shed], key=restore_key) {
        trial = draw + c.demand_kw;
        after = hours_at(st, trial);
        if after > campus.target_hours + RESTORE_MARGIN_H {
            before = hours_at(st, draw);
            c.shed = False;
            draw = trial;
            out.append(ShedRecord(
                action="RESTORE", subject=c.name, tier=c.tier,
                demand_kw=c.demand_kw,
                rule=f"hours_left > target + margin ({campus.target_hours + RESTORE_MARGIN_H:.0f} h) -> restore",
                rationale=f"{c.name} can be re-energised with margin to spare",
                hours_before=before, hours_after=after
            ));
        } else {
            break;
        }
    }

    st.draw_kw = draw;
    st.lit = sorted([f.name for f in loads if not f.shed]);
    st.shed_names = sorted([f.name for f in loads if f.shed]);
    st.hours_left = hours_at(st, draw);
    return out;
}


# ── The control loop ───────────────────────────────────────────────────

"""Write the campus-level rollup from a set of island states."""
def write_campus_stats(campus: Campus, islands: list[IslandState], count: int) {
    worst = HORIZON_H;
    gen = 0.0;
    lit = 0.0;
    for st in islands {
        gen += st.generation_kw;
        lit += st.draw_kw;
        if st.draw_kw > 0.0 and st.hours_left < worst {
            worst = st.hours_left;
        }
    }
    dark = [
        a as Facility for a in assets_of(campus)
        if isinstance(a, Facility) and a.island_id == -1
    ];
    campus.hours_left = worst;
    campus.island_count = count;
    campus.generation_kw = gen;
    campus.lit_load_kw = lit;
    campus.dark_facilities = len(dark);
    campus.dark_tier1 = len([f for f in dark if f.tier == 1]);
}


"""Island and measure, WITHOUT shedding. This is the evidence a decision cites.

Split out from RunTriage on purpose: the audit chain has to record the state
that CAUSED a shed, which means measuring before BLUE acts.
"""
def refresh_state(campus: Campus) -> list[IslandState] {
    count = recompute_islands(campus);
    out: list[IslandState] = [];
    for i in range(count) {
        out.append(measure_island(campus, i));
    }
    write_campus_stats(campus, out, count);
    return out;
}


walker RunTriage {
    """islanding -> hours left -> shedding, in that order, with no AI."""

    has islands: list[IslandState] = [];
    has decisions: list[ShedRecord] = [];

    can run with Campus entry {
        pre = refresh_state(here);
        for st in pre {
            self.decisions += blue_shed(here, st);
        }
        self.islands = refresh_state(here);
        # No `report` here -- it echoes to stdout and this runs several times
        # per tick. Callers read `self.islands` / `self.decisions`.
    }
}
