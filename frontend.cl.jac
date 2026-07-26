"""BLACKSTART - the operator screen.

One page. The grid as dots and lines, a survival clock per island, the live
weather banner, and click-anything-to-kill. Resist adding dashboards.

Every button here spawns the same walker the CLI does. There is no REST
client, no fetch, no JSON parsing and no hand-written API types -- `root spawn
KillAsset(label=...)` in the browser is a generated RPC to the walker in
api.jac, and `Snapshot` arrives as a hydrated typed object.
"""

sv import from .api {
    Snapshot, NodeView, EdgeView, IncidentView, AttackPlan,
    GetSnapshot, Tick, KillAsset, RestoreAsset, GetIncidents, RunRed, ResetGrid
}
sv import from .triage { IslandEnergy }

import from .components.GridMap { GridMap }
import from .components.Panels { IslandCard, IncidentFeed }


def:pub app -> JsxElement {
    has snap: Snapshot | None = None,
        incidents: list[IncidentView] = [],
        selected: str = "",
        redPlan: AttackPlan = AttackPlan(),
        busy: bool = False,
        status: str = "connecting to the grid...";

    async can with entry {
        result = root spawn GetSnapshot();
        if result.reports and len(result.reports) > 0 {
            snap = result.reports[0];
            status = "";
        }
        log = root spawn GetIncidents(limit=12);
        if log.reports and len(log.reports) > 0 {
            incidents = log.reports[0];
        }
    }

    async def reloadIncidents -> None;
    async def doTick -> None;
    async def doTickFast -> None;
    async def doToggle -> None;
    async def doRed -> None;
    async def doReset -> None;

    def pick(label: str) -> None {
        selected = "" if selected == label else label;
    }

    # Derived values are plain locals, never `has`.
    live = snap;
    if live is None {
        return <main className="shell">
            <p className="muted">{status}</p>
        </main>;
    }

    # Flatten to plain scalars before the JSX. A statement slot re-runs every
    # render and type narrowing does not survive into it, so we never carry an
    # optional across that boundary.
    chosenLabel = "";
    chosenAlive = True;
    for n in live.nodes {
        if n.label == selected {
            chosenLabel = n.label;
            chosenAlive = n.alive;
        }
    }
    hasChosen = chosenLabel != "";
    ok = live.survival_hours >= live.target_hours;
    big = ">168" if live.survival_hours >= live.horizon_hours
          else f"{live.survival_hours:.1f}";

    return <main className="shell">
        <header className="top">
            <div>
                <h1>BLACKSTART</h1>
                <p className="sub">
                    {live.base_name + "  -  self-healing microgrid control loop"}
                </p>
            </div>
            <div className={"clock ok" if ok else "clock bad"}>
                <span className="num">{big}</span>
                <span className="unit">{"h  /  " + f"{live.target_hours:.0f} h target"}</span>
                <span className="verdict">{"MISSION INTACT" if ok else "AT RISK"}</span>
            </div>
        </header>

        <div className={"banner alert" if live.weather_alert else "banner"}>
            <b>{"LIVE NWS ALERT" if live.weather_alert else "WEATHER"}</b>
            <span>{live.weather_headline}</span>
            {if live.storm_prep {
                <span className="prep">STORM PREP: charging batteries</span>
            }}
        </div>

        <p className="provenance">
            {"Grid layout: labelled digital twin from public base specifications. "
             + "Weather, alerts and the solar curve: real live public data. "
             + live.provenance}
        </p>

        <section className="stats">
            <div><span>islands</span><b>{str(live.island_count)}</b></div>
            <div><span>dark loads</span><b>{str(live.dark_loads)}</b></div>
            <div><span>sim clock</span><b>{f"{live.sim_hour:04.1f} h"}</b></div>
            <div><span>tick</span><b>{str(live.tick_count)}</b></div>
        </section>

        <section className="controls">
            <button onClick={doTick} disabled={busy}>Advance 15 min</button>
            <button onClick={doTickFast} disabled={busy}>Advance 6 h</button>
            <button className="danger" onClick={doRed} disabled={busy}>
                RED: plan and attack
            </button>
            <button className="ghost" onClick={doReset} disabled={busy}>
                Reset grid
            </button>
            {if hasChosen {
                <button className="kill" onClick={doToggle} disabled={busy}>
                    {("Restore " if not chosenAlive else "Kill ") + chosenLabel}
                </button>
            }}
            {if not hasChosen {
                <span className="hint">click any asset on the map to kill it</span>
            }}
        </section>

        {if len(live.last_actions) > 0 {
            <section className="actions">
                {for (i, a) in enumerate(live.last_actions) {
                    <span className="act" key={"ac" + str(i)}>{a}</span>
                }}
            </section>
        }}

        {if redPlan.target != "" {
            <section className="redbox">
                <h3>{"RED selected: " + redPlan.target}</h3>
                <p>{redPlan.reasoning}</p>
                {if redPlan.runner_up != "" {
                    <p className="muted">{"runner-up: " + redPlan.runner_up}</p>
                }}
                {if redPlan.mitigation != "" {
                    <p className="rec">{"MITIGATION: " + redPlan.mitigation}</p>
                }}
            </section>
        }}

        <section className="body">
            <div className="mapwrap">
                <GridMap nodes={live.nodes} edges={live.edges}
                         selected={selected} onSelect={pick}/>
            </div>
            <aside className="side">
                {for e in live.islands {
                    <IslandCard key={"isl" + str(e.island_id)} island={e}
                                targetHours={live.target_hours}
                                horizon={live.horizon_hours}/>
                }}
                <IncidentFeed incidents={incidents}/>
            </aside>
        </section>

        <footer className="foot">
            DEMO - digital twin. Not connected to any real electrical
            infrastructure. Built in Jac for JacHacks SF.
        </footer>
    </main>;
}
