"""Side panels: island clocks, RED's round log, and the why-chain.

The RED log is where the argument lives. Each round shows what it planned, what
it hit, and -- the part that matters -- the sentence it wrote afterwards. Round
N+1's move exists because of round N's sentence. There is no variable that
holds that.

The why-chain shows one evidence line per graph node, with the node id. That is
the difference between "the AI wrote a summary" and "here is the record".
"""

sv import from ..api { IslandView, EvidenceView, RedRoundView }

import from .GridMap { island_color }


def:pub hours_label(h: float, horizon: float) -> str {
    if h >= horizon {
        return ">240 h";
    }
    return f"{h:.1f} h";
}


def:pub IslandCard(island: IslandView, targetHours: float, horizon: float) -> JsxElement {
    ok = island.hours_left >= targetHours;
    color = island_color(island.island_id);

    return <div className="card" style={{"borderLeftColor": color}}>
        <div className="card-head">
            <span className="pill" style={{"backgroundColor": color}}>
                {"ISLAND " + str(island.island_id)}
            </span>
            <span className="mode">
                {"UTILITY" if island.has_utility else "ISLANDED"}
            </span>
        </div>
        {if island.total_load_kw == 0.0 {
            <p className="muted">Stranded generation - no load on this island.</p>
            skip;
        }}
        <div className={"hours ok" if ok else "hours bad"}>
            {hours_label(island.hours_left, horizon)}
            <span className="verdict">{"MEETS TARGET" if ok else "BELOW TARGET"}</span>
        </div>
        <div className="rows">
            <div><span>energised</span><b>{f"{island.draw_kw:.0f} kW"}</b></div>
            <div><span>of total</span><b>{f"{island.total_load_kw:.0f} kW"}</b></div>
            <div><span>stored</span><b>{f"{island.stored_kwh:.0f} kWh"}</b></div>
        </div>
        {if len(island.shed_names) > 0 {
            <p className="shedline">{"SWITCHED OFF: " + ", ".join(island.shed_names)}</p>
        }}
    </div>;
}


def:pub RedLog(rounds: list[RedRoundView]) -> JsxElement {
    return <div className="feed">
        <h3>RED - what breaks next</h3>
        {if len(rounds) == 0 {
            <p className="muted">
                RED has not run yet. It sees only facility names and status -
                never the wiring - so it has to guess how this campus is
                connected, and learn from what happened.
            </p>
            skip;
        }}
        {for (i, r) in enumerate(rounds) {
            <article className="incident" key={"r" + str(i)}>
                <div className="inc-head">
                    <span className="kind">
                        {"ROUND " + str(r.round) + (" - memory on" if r.memory_on else " - memory OFF")}
                    </span>
                    <span className="ts">{f"{r.min_hours:.1f} h"}</span>
                </div>
                <p className="report">{r.narrative}</p>
                {if len(r.strikes) > 0 {
                    <p className="action">{"HIT: " + ", ".join(r.strikes)}</p>
                }}
                {if len(r.misses) > 0 {
                    <p className="muted">{"missed: " + ", ".join(r.misses)}</p>
                }}
                {if r.lesson != "" {
                    <p className="lesson">{"LEARNED: " + r.lesson}</p>
                }}
                {if r.try_next != "" {
                    <p className="rec">{"NEXT: " + r.try_next}</p>
                }}
                <p className="byline">{r.authored_by}</p>
            </article>
        }}
    </div>;
}


def:pub WhyChain(subject: str, chain: list[EvidenceView]) -> JsxElement {
    return <div className="feed">
        <h3>{"Why did this happen? " + subject}</h3>
        {if len(chain) == 0 {
            <p className="muted">
                Click a facility on the map, then press "Ask why". Hospitals
                spend three weeks reconstructing this from SCADA logs.
            </p>
            skip;
        }}
        {for (i, e) in enumerate(chain) {
            <div className="eline" key={"w" + str(i)}>
                <span className={"etag " + e.kind}>{e.kind}</span>
                <span className="etext">{e.line}</span>
                {if e.node_id != "" {
                    <span className="eid">{"evidence: " + e.node_id}</span>
                }}
            </div>
        }}
    </div>;
}
