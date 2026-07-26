"""Side panels: the per-island survival cards and the incident feed.

The incident feed is where CHRONICLER's writing shows up. Note the byline on
each entry -- it says whether the model wrote it or the offline template did,
because claiming an AI wrote something it did not is exactly the kind of thing
that gets a project disqualified.
"""

sv import from ..api { IncidentView }
sv import from ..triage { IslandEnergy }

import from .GridMap { island_color }


def:pub hours_label(h: float, horizon: float) -> str {
    if h >= horizon {
        return ">168 h";
    }
    return f"{h:.1f} h";
}


def:pub IslandCard(island: IslandEnergy, targetHours: float, horizon: float) -> JsxElement {
    ok = island.survival_hours >= targetHours;
    mode = "GRID-TIED" if island.grid_tie else "ISLANDED";
    color = island_color(island.island_id);

    return <div className="card" style={{"borderLeftColor": color}}>
        <div className="card-head">
            <span className="pill" style={{"backgroundColor": color}}>
                {"ISLAND " + str(island.island_id)}
            </span>
            <span className="mode">{mode}</span>
        </div>
        {if island.total_load_kw == 0.0 {
            <p className="muted">
                Stranded generation - no load on this island.
            </p>
            skip;
        }}
        <div className={"hours ok" if ok else "hours bad"}>
            {hours_label(island.survival_hours, horizon)}
            <span className="verdict">{"INTACT" if ok else "AT RISK"}</span>
        </div>
        <div className="rows">
            <div><span>live load</span><b>{f"{island.load_kw:.0f} kW"}</b></div>
            <div><span>of total</span><b>{f"{island.total_load_kw:.0f} kW"}</b></div>
            <div><span>solar now</span><b>{f"{island.solar_now_kw:.0f} kW"}</b></div>
            <div><span>battery</span><b>{f"{island.batt_kwh:.0f} kWh"}</b></div>
            <div><span>fuel</span><b>{f"{island.fuel_kwh:.0f} kWh"}</b></div>
        </div>
        {if len(island.shed_names) > 0 {
            <p className="shedline">
                {"SHED: " + ", ".join(island.shed_names)}
            </p>
        }}
    </div>;
}


def:pub IncidentFeed(incidents: list[IncidentView]) -> JsxElement {
    return <div className="feed">
        <h3>Incident log</h3>
        {if len(incidents) == 0 {
            <p className="muted">Nothing has happened yet. Kill something.</p>
            skip;
        }}
        {for (i, inc) in enumerate(incidents) {
            <article className="incident" key={"i" + str(i)}>
                <div className="inc-head">
                    <span className="kind">{inc.kind}</span>
                    <span className="ts">{inc.ts}</span>
                </div>
                <p className="detail">{inc.detail}</p>
                {if inc.report != "" {
                    <p className="report">{inc.report}</p>
                }}
                {for (j, a) in enumerate(inc.actions) {
                    <p className="action" key={"a" + str(j)}>{"- " + a}</p>
                }}
                {if inc.recommendation != "" {
                    <p className="rec">{"NEXT: " + inc.recommendation}</p>
                }}
                <p className="byline">{inc.authored_by}</p>
            </article>
        }}
    </div>;
}
