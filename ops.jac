"""BLACKSTART - operator actions and the incident log. NO AI IN THIS FILE.

A storm, a hacker and an operator's mouse click are all the same event to
this system: an asset stopped conducting. There is exactly one code path for
"something died" and everything -- the UI click, the scripted demo, and the
RED agent -- goes through it. RED gets no special powers; it flips the same
boolean a human would.

Timestamps here are wall-clock, but only as a label on the log. No decision
in triage.jac or physics.jac ever reads the clock, which is what keeps the
control loop replayable.
"""

import from datetime { datetime }

import from grid {
    GridNode, GridTie, Solar, Battery, Genset, Feeder, Load, Base,
    IncidentLog, Incident, Feeds, PartOf, Logged
}
import from triage { assets_of }
import from seed { find_log }


"""A stable human-readable name for any asset -- the UI and CLI key on this."""
def asset_label(n: GridNode) -> str {
    if isinstance(n, GridTie) {
        return (n as GridTie).utility;
    }
    if isinstance(n, Solar) {
        return (n as Solar).name;
    }
    if isinstance(n, Battery) {
        return (n as Battery).name;
    }
    if isinstance(n, Genset) {
        return (n as Genset).name;
    }
    if isinstance(n, Feeder) {
        return (n as Feeder).feeder_id;
    }
    if isinstance(n, Load) {
        return (n as Load).name;
    }
    return "unknown";
}


"""Which archetype an asset is -- used for colouring the map."""
def asset_kind(n: GridNode) -> str {
    if isinstance(n, GridTie) { return "gridtie"; }
    if isinstance(n, Solar) { return "solar"; }
    if isinstance(n, Battery) { return "battery"; }
    if isinstance(n, Genset) { return "genset"; }
    if isinstance(n, Feeder) { return "feeder"; }
    if isinstance(n, Load) { return "load"; }
    return "other";
}


"""Find one asset of this base by its label. Returns None if there is no match."""
def find_asset(base: Base, label: str) -> GridNode | None {
    for a in assets_of(base) {
        if asset_label(a) == label {
            return a;
        }
    }
    return None;
}


"""Append an incident to the persistent log and return it."""
def log_incident(
    kind: str, detail: str, survival: float, actions: list[str]
) -> Incident {
    log = find_log();
    inc = Incident(
        ts=datetime.now().strftime("%H:%M:%S"),
        kind=kind,
        detail=detail,
        survival_hours=survival,
        actions=actions
    );
    log +>:Logged:+> inc;
    log.count += 1;
    return inc;
}


"""Every incident, newest first."""
def recent_incidents(limit: int) -> list[Incident] {
    log = find_log();
    all_inc = [log ->:Logged:->];
    return all_inc[-limit:][::-1];
}


"""Take an asset out of service. This is THE kill switch, for every actor.

A grid tie opens its breaker (`live`); anything else is simply destroyed
(`alive`). Both make islanding recompute on the next cycle -- there is no
special-case handling for either.
"""
def kill_asset(base: Base, label: str) -> bool {
    a = find_asset(base, label);
    if a is None {
        return False;
    }
    if isinstance(a, GridTie) {
        (a as GridTie).live = False;
    } else {
        a.alive = False;
        if isinstance(a, Solar) {
            (a as Solar).output_kw = 0.0;
        }
        if isinstance(a, Genset) {
            (a as Genset).output_kw = 0.0;
        }
    }
    return True;
}


"""True if the asset is already out of service (or does not exist).

Counterfactual probes MUST check this first. "Kill it, measure, restore it"
silently turns a dead asset back on if it was already dead when the probe
started -- which would let an attacker's planning phase repair the grid.
"""
def is_down(base: Base, label: str) -> bool {
    a = find_asset(base, label);
    if a is None {
        return True;
    }
    if isinstance(a, GridTie) {
        return not (a as GridTie).live;
    }
    return not a.alive;
}


"""Un-shed every load. Used to unwind a counterfactual probe cleanly, so a
`what if we killed X` question cannot leave the real grid in a shed state.
"""
def clear_shedding(base: Base) {
    for a in assets_of(base) {
        if isinstance(a, Load) {
            (a as Load).shed = False;
        }
    }
}


"""Put an asset back in service."""
def restore_asset(base: Base, label: str) -> bool {
    a = find_asset(base, label);
    if a is None {
        return False;
    }
    if isinstance(a, GridTie) {
        (a as GridTie).live = True;
    } else {
        a.alive = True;
    }
    return True;
}
