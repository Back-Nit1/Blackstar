"""BLACKSTART - the API.

There is no Flask, no FastAPI, no route table and no serializer. Every
`walker:pub` below is automatically a REST endpoint at `/walker/<Name>`, and
the typed `obj`s cross the wire as hydrated instances the client can dot into.
That is a whole infrastructure layer that simply does not exist in this repo.

The frontend needs exactly six verbs: look at the grid, advance time, kill
something, restore something, read the incident log, and turn RED loose.
"""

import from grid {
    GridNode, GridTie, Solar, Battery, Genset, Feeder, Load, Base,
    Incident, Feeds, PartOf
}
import from triage { RunTriage, IslandEnergy, assets_of, SURVIVAL_TARGET_H, HORIZON_H }
import from physics { TickWalker }
import from ops {
    asset_label, asset_kind, kill_asset, restore_asset, log_incident,
    recent_incidents
}
import from seed { ensure_base, rebuild_twin, find_base }
import from agents { Surveyor, RedAgent, AttackPlan, chronicle }


# ── wire types ─────────────────────────────────────────────────────────

obj NodeView {
    has id: str = "";
    has label: str = "";
    has kind: str = "";
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

obj IncidentView {
    has ts: str = "";
    has kind: str = "";
    has detail: str = "";
    has report: str = "";
    has actions: list[str] = [];
    has recommendation: str = "";
    has survival_hours: float = 0.0;
    has authored_by: str = "";
}

obj Snapshot {
    has base_name: str = "";
    has survival_hours: float = 0.0;
    has target_hours: float = 72.0;
    has horizon_hours: float = 168.0;
    has island_count: int = 0;
    has dark_loads: int = 0;
    has sim_hour: float = 0.0;
    has tick_count: int = 0;
    has weather_headline: str = "";
    has weather_alert: bool = False;
    has storm_prep: bool = False;
    has provenance: str = "";
    has nodes: list[NodeView] = [];
    has edges: list[EdgeView] = [];
    has islands: list[IslandEnergy] = [];
    has last_actions: list[str] = [];
}


# ── deterministic layout ───────────────────────────────────────────────
# Positions are computed here, not stored on the graph: where a dot sits on
# screen is presentation, not grid state. Same input always gives the same
# picture, which matters when you demo the same click twice.

glob COL_X: list[float] = [200.0, 500.0, 800.0];


"""One line of live detail per asset, for the tooltip under each dot."""
def node_detail(n: GridNode) -> str {
    if isinstance(n, GridTie) {
        g = n as GridTie;
        return f"{g.capacity_kw:.0f} kW tie - {'CLOSED' if g.live else 'OPEN'}";
    }
    if isinstance(n, Solar) {
        s = n as Solar;
        return f"{s.output_kw:.0f} / {s.capacity_kw:.0f} kW";
    }
    if isinstance(n, Battery) {
        b = n as Battery;
        pct = (b.soc_kwh / b.capacity_kwh * 100.0) if b.capacity_kwh > 0.0 else 0.0;
        return f"{b.soc_kwh:.0f} / {b.capacity_kwh:.0f} kWh  ({pct:.0f}%)";
    }
    if isinstance(n, Genset) {
        gs = n as Genset;
        hrs = (gs.fuel_liters / gs.burn_lph) if gs.burn_lph > 0.0 else 0.0;
        return f"{gs.output_kw:.0f} / {gs.rated_kw:.0f} kW - {gs.fuel_liters:.0f} L ({hrs:.0f} h)";
    }
    if isinstance(n, Load) {
        l = n as Load;
        return f"tier {l.tier} - {l.demand_kw:.0f} kW";
    }
    return "";
}


"""Build the whole picture: nodes with positions, edges, islands, weather."""
def build_snapshot(base: Base, actions: list[str]) -> Snapshot {
    brain = base spawn RunTriage();
    snap = Snapshot(
        base_name=base.name,
        survival_hours=base.survival_hours,
        target_hours=SURVIVAL_TARGET_H,
        horizon_hours=HORIZON_H as float,
        island_count=base.island_count,
        dark_loads=base.dark_loads,
        sim_hour=base.sim_hour,
        tick_count=base.tick_count,
        weather_headline=base.weather_headline,
        weather_alert=base.weather_alert,
        storm_prep=base.storm_prep,
        provenance=base.data_provenance,
        islands=brain.islands,
        last_actions=actions
    );

    assets = assets_of(base);
    feeders = sorted(
        [a as Feeder for a in assets if isinstance(a, Feeder)],
        key=lambda f: Feeder : f.feeder_id
    );
    placed: dict[str, bool] = {};

    # the utility layer, across the top
    for a in assets {
        if isinstance(a, GridTie) {
            snap.nodes.append(view_of(a, 500.0, 50.0));
            placed[jid(a)] = True;
        }
    }
    for a in assets {
        if isinstance(a, Solar) and jid(a) not in placed {
            # a PV array with no feeder above it is the utility-side plant
            parents = [a <-:Feeds:<-];
            if not parents {
                snap.nodes.append(view_of(a, 820.0, 50.0));
                placed[jid(a)] = True;
            }
        }
    }

    # Every feeder gets its column FIRST. Feeders are wired to each other by
    # the normally-closed bus tie, so if we placed children as we walked, the
    # tied feeder would be drawn twice -- once under its neighbour and once in
    # its own column, with a duplicate React key.
    for (fi, f) in enumerate(feeders) {
        cx = COL_X[fi] if fi < len(COL_X) else 200.0 + (fi as float) * 300.0;
        snap.nodes.append(view_of(f, cx, 160.0));
        placed[jid(f)] = True;
    }

    for (fi, f) in enumerate(feeders) {
        cx = COL_X[fi] if fi < len(COL_X) else 200.0 + (fi as float) * 300.0;
        children = sorted(
            [c for c in [f ->:Feeds:->] if jid(c) not in placed], key=asset_label
        );
        sources = [c for c in children if not isinstance(c, Load)];
        loads = [c for c in children if isinstance(c, Load)];
        for (si, s) in enumerate(sources) {
            sx = cx - 90.0 + (si as float) * 90.0;
            snap.nodes.append(view_of(s, sx, 255.0));
            placed[jid(s)] = True;
        }
        for (li, l) in enumerate(loads) {
            lx = cx - 60.0 + ((li % 2) as float) * 120.0;
            ly = 350.0 + (int(li / 2) as float) * 62.0;
            snap.nodes.append(view_of(l, lx, ly));
            placed[jid(l)] = True;
        }
    }

    # anything not placed above still gets a dot -- never silently drop an asset
    spare = 0;
    for a in assets {
        if jid(a) not in placed {
            snap.nodes.append(view_of(a, 60.0, 50.0 + (spare as float) * 40.0));
            placed[jid(a)] = True;
            spare += 1;
        }
    }

    # Two typed edge-filtered queries instead of one loop with an if: the
    # live/cut split is expressed in the query, which is the Jac idiom.
    known = {n.id: True for n in snap.nodes};
    for a in assets {
        src = jid(a);
        if src not in known {
            continue;
        }
        for d in [a ->:Feeds:live == True:->] {          # jac:ignore[W2075]
            if jid(d) in known {
                snap.edges.append(EdgeView(src=src, dst=jid(d), live=True));
            }
        }
        for d in [a ->:Feeds:live == False:->] {         # jac:ignore[W2075]
            if jid(d) in known {
                snap.edges.append(EdgeView(src=src, dst=jid(d), live=False));
            }
        }
    }
    return snap;
}


"""One asset as a drawable dot."""
def view_of(n: GridNode, x: float, y: float) -> NodeView {
    alive = n.alive;
    if isinstance(n, GridTie) {
        alive = (n as GridTie).live;
    }
    return NodeView(
        id=jid(n),
        label=asset_label(n),
        kind=asset_kind(n),
        island_id=n.island_id,
        alive=alive,
        shed=(n as Load).shed if isinstance(n, Load) else False,
        tier=(n as Load).tier if isinstance(n, Load) else 0,
        detail=node_detail(n),
        x=x, y=y
    );
}


"""The incident log as wire objects, newest first."""
def incident_views(limit: int) -> list[IncidentView] {
    out: list[IncidentView] = [];
    for i in recent_incidents(limit) {
        out.append(IncidentView(
            ts=i.ts, kind=i.kind, detail=i.detail, report=i.report,
            actions=i.actions, recommendation=i.recommendation,
            survival_hours=i.survival_hours, authored_by=i.authored_by
        ));
    }
    return out;
}


# ── the endpoints ──────────────────────────────────────────────────────

walker:pub GetSnapshot {
    """GET the whole grid. Builds the twin on first call."""

    has reports: list[Snapshot] = [];

    can run with Root entry {
        base = ensure_base();
        _ = base spawn RunTriage();
        report build_snapshot(base, []);
    }
}


walker:pub Tick {
    """Advance the simulation by `steps` x 15 minutes, then re-survey."""

    has steps: int = 1;
    has reports: list[Snapshot] = [];

    can run with Root entry {
        base = ensure_base();
        actions: list[str] = [];
        for _i in range(max(1, min(self.steps, 96))) {
            t = base spawn TickWalker();
            actions += t.actions;
        }
        _ = base spawn Surveyor();
        report build_snapshot(base, actions);
    }
}


walker:pub KillAsset {
    """Take an asset out of service, re-plan, and have CHRONICLER write it up.

    This is the ONLY kill path. The operator's mouse click, a simulated storm
    and the RED agent all land here.
    """

    has label: str = "";
    has reports: list[Snapshot] = [];

    can run with Root entry {
        base = ensure_base();
        ok = kill_asset(base, self.label);
        if not ok {
            report build_snapshot(base, [f"unknown asset '{self.label}'"]);
            disengage;
        }
        brain = base spawn RunTriage();
        inc = log_incident(
            "asset_loss", f"{self.label} lost", base.survival_hours, brain.actions
        );
        _ = chronicle(inc, brain.islands, base.survival_hours);
        _ = base spawn Surveyor();
        report build_snapshot(base, brain.actions);
    }
}


walker:pub RestoreAsset {
    """Put an asset back in service and let the brain restore load."""

    has label: str = "";
    has reports: list[Snapshot] = [];

    can run with Root entry {
        base = ensure_base();
        ok = restore_asset(base, self.label);
        brain = base spawn RunTriage();
        if ok {
            inc = log_incident(
                "asset_restored", f"{self.label} back in service",
                base.survival_hours, brain.actions
            );
            _ = chronicle(inc, brain.islands, base.survival_hours);
        }
        _ = base spawn Surveyor();
        report build_snapshot(base, brain.actions);
    }
}


walker:pub GetIncidents {
    """The incident log with CHRONICLER's reports, newest first."""

    has limit: int = 12;
    has reports: list[list[IncidentView]] = [];

    can run with Root entry {
        _ = ensure_base();
        report incident_views(max(1, min(self.limit, 100)));
    }
}


walker:pub RunRed {
    """Turn the attacker loose. It plans, then kills through the normal path."""

    has execute: bool = True;
    has reports: list[AttackPlan] = [];

    can run with Root entry {
        base = ensure_base();
        red = base spawn RedAgent(execute=self.execute);
        brain = base spawn RunTriage();
        inc = log_incident(
            "red_team",
            f"RED selected {red.plan.target}: {red.plan.reasoning}",
            base.survival_hours,
            brain.actions
        );
        inc.authored_by = red.authored_by;
        _ = chronicle(inc, brain.islands, base.survival_hours);
        report red.plan;
    }
}


walker:pub ResetGrid {
    """Tear the twin down and rebuild it. The demo reset button."""

    has reports: list[Snapshot] = [];

    can run with Root entry {
        base = rebuild_twin();
        _ = base spawn RunTriage();
        report build_snapshot(base, ["grid rebuilt from seed"]);
    }
}
