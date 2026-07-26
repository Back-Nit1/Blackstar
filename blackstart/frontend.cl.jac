"""BLACKSTART - the operator screen.

One page: the campus as dots and lines, one big number for hours of power left,
and click-anything-to-cut.

Every button spawns the same walker the CLI does. There is no REST client, no
fetch, no JSON parsing and no hand-written API types -- `root spawn
CutAsset(label=...)` in the browser is a generated RPC to the walker in api.jac,
and `GridView` arrives as a hydrated typed object.
"""

sv import from .api {
    GridView, NodeView, EdgeView, IslandView, EvidenceView, RedRoundView,
    GetGrid, Tick, CutAsset, RestoreAsset, AskWhy, RunRedRound, ResetGrid
}

import from .components.GridMap { GridMap }
import from .components.Panels { IslandCard, RedLog, WhyChain }


def:pub app -> JsxElement {
    has grid: GridView | None = None,
        why: list[EvidenceView] = [],
        whySubject: str = "",
        selected: str = "",
        busy: bool = False,
        memoryOn: bool = True,
        status: str = "connecting to the campus...";

    async can with entry {
        result = root spawn GetGrid();
        if result.reports and len(result.reports) > 0 {
            grid = result.reports[0];
            status = "";
        }
    }

    async def doTick -> None;
    async def doToggle -> None;
    async def doWhy -> None;
    async def doRed -> None;
    async def doReset -> None;

    def pick(label: str) -> None {
        selected = "" if selected == label else label;
    }

    def flipMemory(e: MouseEvent) -> None {
        memoryOn = not memoryOn;
    }

    live = grid;
    if live is None {
        return <main className="shell"><p className="muted">{status}</p></main>;
    }

    # Flatten to scalars before the JSX: narrowing does not survive into a
    # statement slot, and a slot re-runs every render.
    chosenLabel = "";
    chosenAlive = True;
    for n in live.nodes {
        if n.label == selected {
            chosenLabel = n.label;
            chosenAlive = n.alive;
        }
    }
    hasChosen = chosenLabel != "";
    ok = live.hours_left >= live.target_hours;
    big = ">240" if live.hours_left >= live.horizon_hours
          else f"{live.hours_left:.1f}";

    return <main className="shell">
        <header className="top">
            <div>
                <h1>BLACKSTART</h1>
                <p className="sub">{live.site}</p>
                <p className="sub2">
                    a hospital (CMS emergency preparedness) and a DoD
                    installation (10 U.S.C. 2925) - the same building
                </p>
            </div>
            <div className={"clock ok" if ok else "clock bad"}>
                <span className="num">{big}</span>
                <span className="unit">
                    {"hours of power left  /  " + f"{live.target_hours:.0f} h target"}
                </span>
                <span className="verdict">
                    {"MEETS TARGET" if ok else "BELOW TARGET"}
                </span>
            </div>
        </header>

        <p className="provenance">{live.provenance}</p>

        <section className="stats">
            <div><span>islands</span><b>{str(live.islands)}</b></div>
            <div><span>dark</span><b>{str(live.dark_facilities)}</b></div>
            <div><span>tier-1 dark</span>
                <b className={"bad" if live.dark_tier1 > 0 else ""}>
                    {str(live.dark_tier1)}
                </b>
            </div>
            <div><span>generation</span><b>{f"{live.generation_kw:.0f} kW"}</b></div>
            <div><span>energised</span><b>{f"{live.lit_load_kw:.0f} kW"}</b></div>
            <div><span>tick</span><b>{str(live.tick)}</b></div>
        </section>

        <section className="controls">
            {if hasChosen {
                <button className="kill" onClick={doToggle} disabled={busy}>
                    {("Restore " if not chosenAlive else "Cut ") + chosenLabel}
                </button>
            }}
            {if hasChosen {
                <button onClick={doWhy} disabled={busy}>
                    {"Ask why: " + chosenLabel}
                </button>
            }}
            {if not hasChosen {
                <span className="hint">click any asset on the map to cut it</span>
            }}
            <button onClick={doTick} disabled={busy}>Advance 15 min</button>
            <button className="danger" onClick={doRed} disabled={busy}>
                RED: next round
            </button>
            <button className="ghost" onClick={flipMemory} disabled={busy}>
                {"RED memory: " + ("ON" if memoryOn else "OFF")}
            </button>
            <button className="ghost" onClick={doReset} disabled={busy}>Reset</button>
        </section>

        {if len(live.last_actions) > 0 {
            <section className="actions">
                {for (i, a) in enumerate(live.last_actions) {
                    <span className="act" key={"ac" + str(i)}>{a}</span>
                }}
            </section>
        }}

        <section className="body">
            <div className="mapwrap">
                <GridMap nodes={live.nodes} edges={live.edges}
                         selected={selected} onSelect={pick}/>
            </div>
            <aside className="side">
                {for isl in live.island_states {
                    <IslandCard key={"i" + str(isl.island_id)} island={isl}
                                targetHours={live.target_hours}
                                horizon={live.horizon_hours}/>
                }}
                <WhyChain subject={whySubject} chain={why}/>
                <RedLog rounds={live.red_rounds}/>
            </aside>
        </section>

        <footer className="foot">
            DEMO - labelled digital twin. Not connected to any real electrical
            infrastructure. Built in Jac for JacHacks SF.
        </footer>
    </main>;
}
