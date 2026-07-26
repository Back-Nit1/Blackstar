"""BLACKSTART - the headless simulation runner.

    jac run sim.jac

Runs the full scripted scenario against a freshly built twin and prints every
decision the control loop makes, then re-runs the same scenario a second time
and asserts the two decision sequences are byte-identical. That second run is
the point: a grid controller that is not replayable is not a grid controller.

Nothing in here is required by the web app -- this is the terminal view of the
exact same walkers the UI spawns.
"""

import from grid { GridNode, GridTie, Solar, Battery, Genset, Load, Base }
import from seed { rebuild_twin }
import from triage { RunTriage, assets_of, SURVIVAL_TARGET_H, HORIZON_H }
import from physics { TickWalker }
import from ops { kill_asset, restore_asset, asset_label, asset_kind }

glob RULE: str = "──────────────────────────────────────────────────────────────";


"""Section header."""
def banner(title: str) {
    print("");
    print(RULE);
    print(f"  {title}");
    print(RULE);
}


"""Format the survival clock against the 72-hour mission target."""
def clock(h: float) -> str {
    if h >= (HORIZON_H as float) {
        return ">168.0 h  (7+ days)";
    }
    verdict = "INTACT" if h >= SURVIVAL_TARGET_H else "AT RISK";
    return f"{h:6.1f} h  vs 72 h target  ->  {verdict}";
}


"""Print the full grid state: islands, survival, what is off, what is dark."""
def show_state(base: Base) {
    print(f"  clock {base.sim_hour:04.1f}h   tick {base.tick_count}"
          f"   islands {base.island_count}   dark loads {base.dark_loads}");
    print(f"  SURVIVAL  {clock(base.survival_hours)}");
    brain = base spawn RunTriage();
    for e in brain.islands {
        gen = "GRID-TIED" if e.grid_tie else "ISLANDED";
        print(f"    island {e.island_id} [{gen}]  load {e.load_kw:7.0f} kW"
              f" of {e.total_load_kw:7.0f} kW   solar {e.solar_now_kw:6.0f} kW"
              f"   batt {e.batt_kwh:7.0f} kWh   fuel {e.fuel_kwh:8.0f} kWh"
              f"   -> {clock(e.survival_hours)}");
        if e.shed_names {
            print(f"      shed: {', '.join(e.shed_names)}");
        }
    }
    dark = sorted([
        asset_label(a) for a in assets_of(base)
        if isinstance(a, Load) and a.island_id == -1
    ]);
    if dark {
        print(f"    DARK (no path to any source): {', '.join(dark)}");
    }
}


"""Advance the simulation and collect every action the brain took."""
def run_ticks(base: Base, n: int, verbose: bool) -> list[str] {
    log: list[str] = [];
    for _i in range(n) {
        t = base spawn TickWalker();
        for a in t.actions {
            log.append(a);
            if verbose {
                print(f"      [t{base.tick_count:03d}] {a}");
            }
        }
    }
    return log;
}


"""The scripted scenario. Returns the ordered list of every decision made."""
def scenario(verbose: bool) -> list[str] {
    base = rebuild_twin();
    trace: list[str] = [];

    if verbose {
        banner("BLACKSTART - self-healing microgrid control loop");
        print(f"  site      {base.name}   ({base.lat}, {base.lon})");
        print(f"  weather   {base.weather_headline}");
        print(f"  data      {base.data_provenance}");
        print("  NOTE      Grid layout is a labelled digital twin.");
        print("            Weather and the solar curve are real live public data.");
        banner("T+0  nominal - city power up");
    }
    trace += run_ticks(base, 2, verbose);
    if verbose { show_state(base); }

    if verbose {
        banner("T+1  CYBER / STORM EVENT - the city tie opens");
        print("  (this is the same edge flip the operator's mouse click uses)");
    }
    _ = kill_asset(base, "Southern California Edison");
    trace.append("KILL Southern California Edison");
    trace += run_ticks(base, 2, verbose);
    if verbose {
        show_state(base);
        print("  note: the 31 MW utility PV array sat on the grid side of the");
        print("        point of common coupling, so it dropped out with the tie.");
    }

    if verbose { banner("T+2  ASSET LOSS - BESS-1 destroyed"); }
    _ = kill_asset(base, "BESS-1");
    trace.append("KILL BESS-1");
    trace += run_ticks(base, 2, verbose);
    if verbose { show_state(base); }

    if verbose { banner("T+3  RECOVERY - city power restored"); }
    _ = restore_asset(base, "Southern California Edison");
    trace.append("RESTORE Southern California Edison");
    trace += run_ticks(base, 4, verbose);
    if verbose { show_state(base); }

    return trace;
}


with entry:__main__ {
    first = scenario(True);

    banner("DETERMINISM CHECK - same scenario, second run");
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
