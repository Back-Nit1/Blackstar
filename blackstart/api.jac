"""BLACKSTART - the API.

No Flask, no FastAPI, no route table, no serialiser. Every `walker:pub` here is
automatically `POST /walker/<Name>`, and the typed objects cross the wire as
hydrated instances. That is an entire infrastructure layer that does not exist
in this repo.

The screen needs seven verbs: look at the campus, advance time, cut something,
restore something, ask why, turn RED loose, and reset.
"""

import from grid {
    GridNode, UtilityTie, Substation, Feeder, TieSwitch, Generator, Battery,
    SupplyRoute, Facility, Campus, RedRound, Feeds, PartOf, Logged
}
import from triage {
    RunTriage, IslandState, assets_of, refresh_state, TARGET_H, HORIZON_H
}
import from physics { TickWalker }
import from ops {
    asset_label, asset_kind, kill_asset, restore_asset, is_down, Evidence,
    WhyWalker
}
import from seed { ensure_campus, rebuild_campus }
import from agents { RedAgent }


# ── wire types ─────────────────────────────────────────────────────────

obj NodeView {
    has id: str = "";
    has label: str = "";
    has kind: str = "";
    has building: str = "";
    has island_id: int = -1;
    has alive: bool = True;
    has shed: bool = False;
    has tier: int = 0;
    has detail: str = "";
    has x: float = 0.0;
    has y: float = 0.0;
}

obj EdgeView {
    has src: str = "";
    has dst: str = "";
    has live: bool = True;
}

obj IslandView {
    has island_id: int = 0;
    has hours_left: float = 0.0;
    has draw_kw: float = 0.0;
    has total_load_kw: float = 0.0;
    has stored_kwh: float = 0.0;
    has has_utility: bool = False;
    has shed_names: list[str] = [];
}

obj EvidenceView {
    has node_id: str = "";
    has tick: int = 0;
    has kind: str = "";
    has line: str = "";
}

obj RedRoundView {
    has round: int = 0;
    has narrative: str = "";
    has strikes: list[str] = [];
    has misses: list[str] = [];
    has lesson: str = "";
    has try_next: str = "";
    has dark_tier1: int = 0;
    has min_hours: float = 0.0;
    has memory_on: bool = True;
    has authored_by: str = "";
}

obj GridView {
    has site: str = "";
    has provenance: str = "";
    has hours_left: float = 0.0;
    has target_hours: float = 96.0;
    has horizon_hours: float = 240.0;
    has islands: int = 0;
    has dark_facilities: int = 0;
    has dark_tier1: int = 0;
    has generation_kw: float = 0.0;
    has lit_load_kw: float = 0.0;
    has tick: int = 0;
    has nodes: list[NodeView] = [];
    has edges: list[EdgeView] = [];
    has island_states: list[IslandView] = [];
    has last_actions: list[str] = [];
    has red_rounds: list[RedRoundView] = [];
}


# ── deterministic layout ───────────────────────────────────────────────
# Where a dot sits on screen is presentation, not grid state, so positions are
# computed here rather than stored. The same campus always draws the same
# picture, which matters when you demo the same click twice.

"""One line of live detail per asset, for the label under each dot."""
def node_detail(n: GridNode) -> str {
    if isinstance(n, UtilityTie) {
        u = n as UtilityTie;
        return f"{u.capacity_kw:.0f} kW - {'CLOSED' if u.live else 'OPEN'}";
    }
    if isinstance(n, Generator) {
        g = n as Generator;
        hrs = ((g.fuel_liters + g.bulk_liters) / g.burn_lph) if g.burn_lph > 0.0 else 0.0;
        return f"{g.rated_kw:.0f} kW - {hrs:.0f} h fuel";
    }
    if isinstance(n, Battery) {
        b = n as Battery;
        return f"{b.soc_kwh:.0f} / {b.capacity_kwh:.0f} kWh";
    }
    if isinstance(n, Facility) {
        f = n as Facility;
        return f"tier {f.tier} - {f.demand_kw:.0f} kW";
    }
    if isinstance(n, SupplyRoute) {
        return "fuel route";
    }
    return "";
}


"""One asset as a drawable dot."""
def view_of(n: GridNode, x: float, y: float) -> NodeView {
    alive = n.alive;
    if isinstance(n, UtilityTie) {
        alive = (n as UtilityTie).live;
    }
    return NodeView(
        id=jid(n), label=asset_label(n), kind=asset_kind(n),
        building=(n as Facility).building if isinstance(n, Facility) else "",
        island_id=n.island_id, alive=alive,
        shed=(n as Facility).shed if isinstance(n, Facility) else False,
        tier=(n as Facility).tier if isinstance(n, Facility) else 0,
        detail=node_detail(n), x=x, y=y
    );
}


"""Lay the campus out: utility on top, substations, plant, feeders, buildings."""
def layout(campus: Campus, view: GridView) {
    assets = assets_of(campus);
    placed: dict[str, bool] = {};

    for a in assets {
        if isinstance(a, UtilityTie) {
            view.nodes.append(view_of(a, 500.0, 40.0));
            placed[jid(a)] = True;
        }
    }
    subs = sorted(
        [a for a in assets if isinstance(a, Substation)], key=asset_label
    );
    col: dict[str, float] = {};
    for (i, s) in enumerate(subs) {
        x = 260.0 + (i as float) * 480.0;
        col[jid(s)] = x;
        view.nodes.append(view_of(s, x, 130.0));
        placed[jid(s)] = True;
    }
    for a in sorted([a for a in assets if isinstance(a, TieSwitch)], key=asset_label) {
        view.nodes.append(view_of(a, 500.0, 130.0));
        placed[jid(a)] = True;
    }

    # plant and roads sit under the substation that feeds them
    for (i, s) in enumerate(subs) {
        kids = sorted(
            [
                k for k in [s ->:Feeds:->]
                if jid(k) not in placed and not isinstance(k, Feeder)
            ],
            key=asset_label
        );
        base_x = col[jid(s)];
        for (j, k) in enumerate(kids) {
            view.nodes.append(view_of(k, base_x - 110.0 + (j as float) * 110.0, 225.0));
            placed[jid(k)] = True;
        }
    }
    for a in sorted([a for a in assets if isinstance(a, SupplyRoute)], key=asset_label) {
        if jid(a) not in placed {
            view.nodes.append(view_of(a, 60.0, 225.0 + (len(placed) % 2 as float) * 0.0));
            placed[jid(a)] = True;
        }
    }

    feeders = sorted([a for a in assets if isinstance(a, Feeder)], key=asset_label);
    for (i, f) in enumerate(feeders) {
        fx = 190.0 + (i as float) * 310.0;
        view.nodes.append(view_of(f, fx, 320.0));
        placed[jid(f)] = True;
        kids = sorted(
            [k for k in [f ->:Feeds:->] if jid(k) not in placed], key=asset_label
        );
        for (j, k) in enumerate(kids) {
            kx = fx - 65.0 + ((j % 2) as float) * 130.0;
            ky = 400.0 + (int(j / 2) as float) * 66.0;
            view.nodes.append(view_of(k, kx, ky));
            placed[jid(k)] = True;
        }
    }
    # never silently drop an asset
    spare = 0;
    for a in assets {
        if jid(a) not in placed {
            view.nodes.append(view_of(a, 60.0, 60.0 + (spare as float) * 46.0));
            placed[jid(a)] = True;
            spare += 1;
        }
    }

    # Two typed edge queries instead of one loop with an if: the live/cut split
    # is expressed in the query, which is the Jac idiom.
    known = {n.id: True for n in view.nodes};
    for a in assets {
        src = jid(a);
        if src not in known {
            continue;
        }
        for d in [a ->:Feeds:live == True:->] {          # jac:ignore[W2075]
            if jid(d) in known {
                view.edges.append(EdgeView(src=src, dst=jid(d), live=True));
            }
        }
        for d in [a ->:Feeds:live == False:->] {         # jac:ignore[W2075]
            if jid(d) in known {
                view.edges.append(EdgeView(src=src, dst=jid(d), live=False));
            }
        }
    }
}


"""RED's memory, newest round first."""
def red_log(campus: Campus, limit: int) -> list[RedRoundView] {
    rounds = sorted(
        [r for r in [campus ->:Logged:->]], key=lambda r: RedRound : -r.round
    );
    out: list[RedRoundView] = [];
    for r in rounds[:limit] {
        out.append(RedRoundView(
            round=r.round, narrative=r.narrative, strikes=r.strikes,
            misses=r.misses, lesson=r.lesson, try_next=r.try_next,
            dark_tier1=r.dark_tier1, min_hours=r.min_hours,
            memory_on=r.memory_on, authored_by=r.authored_by
        ));
    }
    return out;
}


"""Build the whole picture the screen reads."""
def build_view(campus: Campus, actions: list[str]) -> GridView {
    states = refresh_state(campus);
    view = GridView(
        site=campus.name, provenance=campus.provenance,
        hours_left=campus.hours_left, target_hours=campus.target_hours,
        horizon_hours=HORIZON_H, islands=campus.island_count,
        dark_facilities=campus.dark_facilities, dark_tier1=campus.dark_tier1,
        generation_kw=campus.generation_kw, lit_load_kw=campus.lit_load_kw,
        tick=campus.tick, last_actions=actions,
        red_rounds=red_log(campus, 6)
    );
    for st in states {
        view.island_states.append(IslandView(
            island_id=st.island_id, hours_left=st.hours_left,
            draw_kw=st.draw_kw, total_load_kw=st.total_load_kw,
            stored_kwh=st.stored_kwh, has_utility=st.has_utility,
            shed_names=st.shed_names
        ));
    }
    layout(campus, view);
    return view;
}


# ── the endpoints ──────────────────────────────────────────────────────

walker:pub GetGrid {
    """The whole campus. Builds the twin on first call."""

    has reports: list[GridView] = [];

    can run with Root entry {
        campus = ensure_campus();
        if campus.tick == 0 {
            _ = campus spawn TickWalker();
        }
        report build_view(campus, []);
    }
}


walker:pub Tick {
    """Advance the simulation by `steps` x 15 minutes."""

    has steps: int = 1;
    has reports: list[GridView] = [];

    can run with Root entry {
        campus = ensure_campus();
        actions: list[str] = [];
        for _i in range(max(1, min(self.steps, 96))) {
            t = campus spawn TickWalker();
            actions += t.actions;
        }
        report build_view(campus, actions);
    }
}


walker:pub CutAsset {
    """Cut a cable or take an asset out. THE kill path, shared with RED."""

    has label: str = "";
    has reports: list[GridView] = [];

    can run with Root entry {
        campus = ensure_campus();
        if not kill_asset(campus, self.label) {
            report build_view(campus, [f"unknown asset '{self.label}'"]);
            disengage;
        }
        t = campus spawn TickWalker(
            cause_kind="cut", cause_target=self.label, cause_actor="operator"
        );
        report build_view(campus, t.actions);
    }
}


walker:pub RestoreAsset {
    """Put an asset back and let BLUE re-energise what it can."""

    has label: str = "";
    has reports: list[GridView] = [];

    can run with Root entry {
        campus = ensure_campus();
        ok = restore_asset(campus, self.label);
        t = campus spawn TickWalker(
            cause_kind=("restore" if ok else ""), cause_target=self.label,
            cause_actor="operator"
        );
        report build_view(campus, t.actions);
    }
}


walker:pub AskWhy {
    """Walk the evidence backwards. Every line cites a real graph node."""

    has subject: str = "";
    has reports: list[list[EvidenceView]] = [];

    can run with Root entry {
        campus = ensure_campus();
        why = campus spawn WhyWalker(subject=self.subject);
        out: list[EvidenceView] = [];
        for e in why.chain {
            out.append(EvidenceView(
                node_id=e.node_id, tick=e.tick, kind=e.kind, line=e.line
            ));
        }
        report out;
    }
}


walker:pub RunRedRound {
    """One round of RED: LOOK -> PLAN -> RUN -> REFLECT."""

    has memory_on: bool = True;
    has reports: list[GridView] = [];

    can run with Root entry {
        campus = ensure_campus();
        n = len([r for r in [campus ->:Logged:->]]);
        red = campus spawn RedAgent(round_no=n + 1, memory_on=self.memory_on);
        note = red.narrative if not red.failed else red.authored_by;
        report build_view(campus, ["RED round " + str(n + 1) + ": " + note]);
    }
}


walker:pub ResetGrid {
    """Rebuild the twin, clearing RED's memory and the whole audit chain."""

    has reports: list[GridView] = [];

    can run with Root entry {
        campus = rebuild_campus();
        _ = campus spawn TickWalker();
        report build_view(campus, ["campus reset from seed"]);
    }
}
