"""BLACKSTART - headless runner.

    jac script sim

Runs the scripted failure, prints every decision BLUE made, then runs the
identical failure a second time and diffs the two decision traces. A grid
controller that is not replayable is not a grid controller.
"""

import os;

import from grid { GridNode, Facility, Generator, Battery, Campus }
import from seed { rebuild_campus }
import from triage { RunTriage, IslandState, assets_of, TARGET_H, HORIZON_H }
import from physics { TickWalker }
import from ops { kill_asset, restore_asset, asset_label, WhyWalker }
import from agents { RedAgent, Outcome }

glob RULE: str = "──────────────────────────────────────────────────────────────";


def banner(title: str) {
    print("");
    print(RULE);
    print(f"  {title}");
    print(RULE);
}


"""Format hours against the 96-hour planning target."""
def clock(h: float) -> str {
    if h >= HORIZON_H {
        return ">240 h  (utility up)";
    }
    verdict = "MEETS TARGET" if h >= TARGET_H else "BELOW TARGET";
    return f"{h:6.1f} h  vs {TARGET_H:.0f} h  ->  {verdict}";
}


def show(campus: Campus) {
    print(f"  tick {campus.tick}   islands {campus.island_count}"
          f"   dark {campus.dark_facilities} (tier-1: {campus.dark_tier1})");
    print(f"  HOURS LEFT  {clock(campus.hours_left)}");
    brain = campus spawn RunTriage();
    for st in brain.islands {
        mode = "UTILITY" if st.has_utility else "ISLANDED";
        print(f"    island {st.island_id} [{mode}]  lit {st.draw_kw:6.0f} kW"
              f" of {st.total_load_kw:6.0f} kW   stored {st.stored_kwh:8.0f} kWh"
              f"   -> {clock(st.hours_left)}");
        if st.shed_names {
            print(f"      shed: {', '.join(st.shed_names)}");
        }
    }
    dark = sorted([
        (a as Facility).name for a in assets_of(campus)
        if isinstance(a, Facility) and a.island_id == -1
    ]);
    if dark {
        print(f"    DARK (no path to any source): {', '.join(dark)}");
    }
}


"""Advance the world, optionally attributing the cause for the audit chain."""
def step(
    campus: Campus, n: int, kind: str, target: str, actor: str, verbose: bool
) -> list[str] {
    log: list[str] = [];
    for i in range(n) {
        t = campus spawn TickWalker(
            cause_kind=(kind if i == 0 else ""),
            cause_target=(target if i == 0 else ""),
            cause_actor=actor
        );
        for a in t.actions {
            log.append(a);
            if verbose {
                print(f"      [t{campus.tick:03d}] {a}");
            }
        }
    }
    return log;
}


"""The scripted failure. Returns the ordered list of every decision made."""
def scenario(verbose: bool) -> list[str] {
    campus = rebuild_campus();
    trace: list[str] = [];

    if verbose {
        banner("BLACKSTART - " + campus.name);
        print(f"  site       36.8354, -76.3044   Elizabeth River, Portsmouth VA");
        print(f"  mandate    hospital (CMS emergency preparedness) AND");
        print(f"             DoD installation (10 U.S.C. 2925)");
        print(f"  data       {campus.provenance}");
        banner("T+0  nominal - commercial power up");
    }
    trace += step(campus, 1, "", "", "operator", verbose);
    if verbose { show(campus); }

    if verbose { banner("T+1  the Dominion Energy Feed is cut"); }
    _ = kill_asset(campus, "Dominion Energy Feed");
    trace.append("CUT Dominion Energy Feed");
    trace += step(campus, 2, "cut", "Dominion Energy Feed", "operator", verbose);
    if verbose { show(campus); }

    if verbose { banner("T+2  the Campus Bus Tie opens too - the split goes wrong"); }
    _ = kill_asset(campus, "Campus Bus Tie");
    trace.append("CUT Campus Bus Tie");
    trace += step(campus, 2, "cut", "Campus Bus Tie", "operator", verbose);
    if verbose { show(campus); }

    if verbose { banner("T+3  the fuel route floods - the truck cannot get through"); }
    _ = kill_asset(campus, "Gate 2 Fuel Delivery Route");
    trace.append("CUT Gate 2 Fuel Delivery Route");
    trace += step(campus, 2, "cut", "Gate 2 Fuel Delivery Route", "operator", verbose);
    if verbose { show(campus); }

    return trace;
}


"""Is a model key present? Checked up front so a keyless run stays readable.

Without this the provider SDK dumps a 30-line HTTP error into the middle of
the demo output. RED still refuses to fake it -- we just say so in one line.
"""
def have_model_key() -> bool {
    for name in ["GEMINI_API_KEY", "GOOGLE_API_KEY"] {
        if os.environ.get(name, "") {
            return True;
        }
    }
    return False;
}


"""Run RED for N rounds and report the damage it achieved.

`memory_on=False` gives every round an empty lesson list, so RED starts from
scratch each time. That is the control. With memory on, each round is handed
the sentences it wrote in the rounds before it.
"""
def red_run(rounds: int, memory_on: bool, verbose: bool) -> list[float] {
    campus = rebuild_campus();
    _ = campus spawn TickWalker();
    worst = 240.0;
    dark_t1 = 0;
    for r in range(1, rounds + 1) {
        red = campus spawn RedAgent(round_no=r, memory_on=memory_on);
        if red.failed {
            print(f"    round {r}: {red.authored_by}");
            return [];
        }
        if red.outcome.min_hours < worst {
            worst = red.outcome.min_hours;
        }
        dark_t1 = max(dark_t1, red.outcome.dark_tier1);
        if verbose {
            print(f"    round {r}  hit {red.hit}"
                  + (f"  missed {red.missed}" if red.missed else ""));
            print(f"      plan:   {red.narrative}");
            print(f"      result: {red.outcome.islands} island(s), "
                  f"min hours {red.outcome.min_hours}, "
                  f"tier-1 dark {red.outcome.dark_tier1}");
            if red.lesson {
                print(f"      LESSON: {red.lesson}");
                print(f"      NEXT:   {red.try_next}");
            }
            print("");
        }
    }
    return [worst, dark_t1 as float];
}


with entry:__main__ {
    first = scenario(True);

    banner("WHY DID THE CAFETERIA GO DARK?");
    campus = [root --> [?:Campus]][0];
    why = campus spawn WhyWalker(subject="Cafeteria - Charette");
    for e in why.chain {
        tag = f"[{e.kind}]".ljust(12);
        print(f"  {tag} {e.line}");
        if e.node_id {
            print(f"               evidence: {e.node_id}");
        }
    }

    off: list[float] = [];
    on: list[float] = [];
    if not have_model_key() {
        banner("RED - SKIPPED");
        print("  No GEMINI_API_KEY / GOOGLE_API_KEY in the environment.");
        print("  RED has no offline fallback on purpose: a scripted attacker");
        print("  would disprove the one thing this agent exists to show.");
        print("");
        print("    export GEMINI_API_KEY=...   # aistudio.google.com");
    } else {
        banner("RED - MEMORY OFF (control): 3 rounds, no lessons carried");
        off = red_run(3, False, True);

        banner("RED - MEMORY ON: 3 rounds, each handed the previous lessons");
        on = red_run(3, True, True);
    }

    if off and on {
        print(f"  memory OFF  worst hours {off[0]:.1f}   tier-1 dark {off[1]:.0f}");
        print(f"  memory ON   worst hours {on[0]:.1f}   tier-1 dark {on[1]:.0f}");
        better = (on[0] < off[0]) or (on[1] > off[1]);
        print(f"  -> memory {'WINS' if better else 'did NOT beat control'}");
    }

    banner("DETERMINISM CHECK - same failure, second run");
    second = scenario(False);
    if first == second {
        print(f"  PASS  {len(first)} decisions, identical on both runs.");
    } else {
        print("  FAIL  the two runs diverged:");
        for i in range(max(len(first), len(second))) {
            a = first[i] if i < len(first) else "<none>";
            b = second[i] if i < len(second) else "<none>";
            if a != b {
                print(f"    [{i}] run1={a}  run2={b}");
            }
        }
    }
    print("");
}
