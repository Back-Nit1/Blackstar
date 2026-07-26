"""BLACKSTART - the one kill path, and the audit chain. NO AI IN THIS FILE.

A flood, an operator's mouse click and the RED agent are the same event to this
system: an asset stopped working. There is exactly one function for it, and
everything goes through it. RED gets no special powers -- it flips the same
boolean a human would, and BLUE responds the same way.

The audit chain is the other half. "Why did the third floor go dark at 2:03?"
is a three-week SCADA archaeology project today. Here every decision is a node
with edges pointing at the evidence that produced it, recorded as it happens.
Answering the question is a graph walk, not a reconstruction.
"""

import from grid {
    GridNode, UtilityTie, Substation, Feeder, TieSwitch, Generator, Battery,
    SupplyRoute, Facility, Campus, Snapshot, Event, Decision,
    Feeds, PartOf, Follows, Observed, Because, Triggered, Affected
}
import from triage { assets_of, ShedRecord }


obj Evidence {
    """One citable line in a why-chain. `node_id` is a real graph id."""

    has node_id: str = "";
    has tick: int = 0;
    has kind: str = "";
    has line: str = "";
}


# ── naming ─────────────────────────────────────────────────────────────

"""The one human-readable name for any asset. RED sees only these."""
def asset_label(n: GridNode) -> str {
    if isinstance(n, UtilityTie) { return (n as UtilityTie).utility; }
    if isinstance(n, Substation) { return (n as Substation).name; }
    if isinstance(n, TieSwitch) { return (n as TieSwitch).name; }
    if isinstance(n, Generator) { return (n as Generator).name; }
    if isinstance(n, Battery) { return (n as Battery).name; }
    if isinstance(n, SupplyRoute) { return (n as SupplyRoute).name; }
    if isinstance(n, Feeder) { return (n as Feeder).feeder_id; }
    if isinstance(n, Facility) { return (n as Facility).name; }
    return "unknown";
}


"""Which archetype an asset is -- used for colouring the map."""
def asset_kind(n: GridNode) -> str {
    if isinstance(n, UtilityTie) { return "utility"; }
    if isinstance(n, Substation) { return "substation"; }
    if isinstance(n, TieSwitch) { return "tieswitch"; }
    if isinstance(n, Generator) { return "generator"; }
    if isinstance(n, Battery) { return "battery"; }
    if isinstance(n, SupplyRoute) { return "route"; }
    if isinstance(n, Feeder) { return "feeder"; }
    if isinstance(n, Facility) { return "facility"; }
    return "other";
}


"""Exact label match."""
def find_asset(campus: Campus, label: str) -> GridNode | None {
    for a in assets_of(campus) {
        if asset_label(a) == label {
            return a;
        }
    }
    return None;
}


"""Resolve a name RED guessed at to a real asset.

RED never sees the graph, so it names things the way a person would -- "North
Substation", "the basement generator". We match generously: exact, then
case-insensitive, then substring, then word overlap. A name that resolves to
nothing is a MISS, which is logged and costs RED its move. Real attackers guess
wrong too, and that is part of the point.
"""
def resolve_target(campus: Campus, guess: str) -> GridNode | None {
    want = guess.strip().lower();
    if not want {
        return None;
    }
    assets = sorted(assets_of(campus), key=asset_label);
    for a in assets {
        if asset_label(a).lower() == want {
            return a;
        }
    }
    for a in assets {
        lab = asset_label(a).lower();
        if want in lab or lab in want {
            return a;
        }
    }
    want_words = set([w for w in want.replace("-", " ").split() if len(w) > 3]);
    best: GridNode | None = None;
    best_score = 0;
    for a in assets {
        lab_words = set([
            w for w in asset_label(a).lower().replace("-", " ").split() if len(w) > 3
        ]);
        score = len(want_words & lab_words);
        if score > best_score {
            best_score = score;
            best = a;
        }
    }
    return best if best_score > 0 else None;
}


# ── the one kill path ──────────────────────────────────────────────────

"""Is this asset already out of service?"""
def is_down(campus: Campus, label: str) -> bool {
    a = find_asset(campus, label);
    if a is None {
        return True;
    }
    if isinstance(a, UtilityTie) {
        return not (a as UtilityTie).live;
    }
    return not a.alive;
}


"""Take an asset out of service. THE kill switch, for every actor."""
def kill_asset(campus: Campus, label: str) -> bool {
    a = find_asset(campus, label);
    if a is None {
        return False;
    }
    if isinstance(a, UtilityTie) {
        (a as UtilityTie).live = False;
    } else {
        a.alive = False;
        if isinstance(a, Generator) {
            (a as Generator).output_kw = 0.0;
        }
    }
    return True;
}


"""Put an asset back in service."""
def restore_asset(campus: Campus, label: str) -> bool {
    a = find_asset(campus, label);
    if a is None {
        return False;
    }
    if isinstance(a, UtilityTie) {
        (a as UtilityTie).live = True;
    } else {
        a.alive = True;
    }
    return True;
}


"""Un-shed everything. Used to reset between A/B runs."""
def clear_shedding(campus: Campus) {
    for a in assets_of(campus) {
        if isinstance(a, Facility) {
            (a as Facility).shed = False;
        }
    }
}


# ── the audit chain ────────────────────────────────────────────────────

"""Every snapshot on the campus, newest first."""
def snapshots_of(campus: Campus) -> list[Snapshot] {
    got = [
        a as Snapshot for a in assets_of(campus) if isinstance(a, Snapshot)
    ];
    return sorted(got, key=lambda s: Snapshot : -s.tick);
}


"""The most recent snapshot, if any."""
def latest_snapshot(campus: Campus) -> Snapshot | None {
    got = snapshots_of(campus);
    return got[0] if got else None;
}


"""Record the state of the campus at this tick and chain it to the previous."""
def record_snapshot(campus: Campus) -> Snapshot {
    prev = latest_snapshot(campus);
    snap = Snapshot(
        tick=campus.tick,
        islands=campus.island_count,
        hours_left=campus.hours_left,
        generation_kw=campus.generation_kw,
        lit_load_kw=campus.lit_load_kw,
        dark_tier1=campus.dark_tier1
    );
    snap +>:PartOf:+> campus;
    if prev is not None {
        snap +>:Follows:+> prev;
    }
    return snap;
}


"""Record something that happened TO the grid, attached to the current tick."""
def record_event(
    campus: Campus, snap: Snapshot, kind: str, target: str,
    detail: str, actor: str
) -> Event {
    ev = Event(
        tick=campus.tick, kind=kind, target=target, detail=detail, actor=actor
    );
    ev +>:PartOf:+> campus;
    snap +>:Observed:+> ev;
    return ev;
}


"""Record a BLUE decision with its evidence attached. No uncited decisions."""
def record_decision(
    campus: Campus, snap: Snapshot, cause: Event | None,
    rec: ShedRecord, subject: Facility | None
) -> Decision {
    d = Decision(
        tick=campus.tick, action=rec.action, subject=rec.subject,
        tier=rec.tier, rule=rec.rule,
        rationale=(
            f"{rec.rationale}. Hours left {rec.hours_before:.1f} -> "
            f"{rec.hours_after:.1f} against a {campus.target_hours:.0f} h target."
        )
    );
    d +>:PartOf:+> campus;
    d +>:Because:+> snap;           # the evidence -- always present
    if cause is not None {
        cause +>:Triggered:+> d;
    }
    if subject is not None {
        d +>:Affected:+> subject;
    }
    return d;
}


# ── "why did the cafeteria go dark?" ───────────────────────────────────

walker WhyWalker {
    """Walk the evidence backwards from a decision and cite every step.

    This is the answer to the question hospitals currently spend three weeks
    reconstructing from SCADA logs. Here it is a graph traversal, and every
    line carries the id of the node it came from.
    """

    has subject: str = "";
    has max_events: int = 4;
    has chain: list[Evidence] = [];

    can start with Campus entry {
        # Keep a list rather than an optional: narrowing does not survive into
        # a `visit`, and an empty list is the same "not found" signal.
        hits: list[Decision] = [];
        best_tick = -1;
        for a in assets_of(here) {
            if isinstance(a, Decision) {
                d = a as Decision;
                if d.subject == self.subject and d.tick >= best_tick {
                    best_tick = d.tick;
                    hits = [d];
                }
            }
        }
        if not hits {
            self.chain.append(Evidence(
                kind="none",
                line=f"No recorded decision affected '{self.subject}'."
            ));
            disengage;
        }
        visit hits;
    }

    can explain with Decision entry {
        self.chain.append(Evidence(
            node_id=jid(here), tick=here.tick, kind="decision",
            line=f"tick {here.tick}: {here.action} {here.subject} "
                 f"(tier {here.tier}) - {here.rule}"
        ));
        self.chain.append(Evidence(
            node_id=jid(here), tick=here.tick, kind="rationale",
            line=here.rationale
        ));
        visit [here ->:Because:->];
    }

    can evidence with Snapshot entry {
        self.chain.append(Evidence(
            node_id=jid(here), tick=here.tick, kind="state",
            line=f"tick {here.tick}: {here.islands} island(s), generation "
                 f"{here.generation_kw:.0f} kW, energised load "
                 f"{here.lit_load_kw:.0f} kW, hours left {here.hours_left:.1f}"
        ));
        seen = 0;
        for ev in [here ->:Observed:->] {
            if seen >= self.max_events {
                break;
            }
            self.chain.append(Evidence(
                node_id=jid(ev), tick=ev.tick, kind="event",
                line=f"tick {ev.tick}: {ev.actor} {ev.kind} - {ev.target}"
                     + (f" ({ev.detail})" if ev.detail else "")
            ));
            seen += 1;
        }
        # One hop further back is enough to show the before-and-after.
        for older in [here ->:Follows:->] {
            self.chain.append(Evidence(
                node_id=jid(older), tick=older.tick, kind="before",
                line=f"tick {older.tick} (before): generation "
                     f"{older.generation_kw:.0f} kW, hours left "
                     f"{older.hours_left:.1f}"
            ));
            break;
        }
        disengage;
    }
}
