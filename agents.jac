"""BLACKSTART - the AI helpers.

THE GOLDEN RULE, in one sentence:
    the brain decides; the AI only explains, imagines, and attacks.

Every agent here reads the *outputs* of triage.jac. None of them can shed a
load, open a breaker by fiat, or change the survival clock. If an LLM ever
made the shedding decision the system would stop being predictable, and
predictability is the entire safety story.

  SURVEYOR    no AI at all -- the senses. Notices change, logs incidents,
              pre-charges the batteries on a real NWS alert.
  CHRONICLER  AI. Turns decisions ALREADY MADE into a plain-English incident
              report. Its inputs are the brain's outputs, never raw state,
              so it has nothing to hallucinate about.
  ORACLE      AI. Counterfactuals. The CODE re-runs the survival math for the
              alternative; the model only contrasts the two in words.
  RED         AI. The attacker. Modelled on CISA advisory AA24-038A (Volt
              Typhoon: state actors pre-positioned inside US power
              infrastructure). It has to PLAN -- read the grid, probe
              consequences with real tool calls, and pick the single most
              damaging target. Then it kills that target through the exact
              same edge flip the operator's mouse click uses.
"""

import from byllm.lib { Model }

import from grid { GridNode, GridTie, Solar, Battery, Genset, Load, Base, Incident }
import from triage { RunTriage, IslandEnergy, assets_of, SURVIVAL_TARGET_H, HORIZON_H }
import from ops {
    asset_label, asset_kind, kill_asset, restore_asset, clear_shedding,
    log_incident, is_down
}
import from seed { find_base }

# Defenders run on Gemini. The key comes from GEMINI_API_KEY / GOOGLE_API_KEY
# in the environment and is never committed. Every call site degrades to a
# deterministic template if the key is missing -- every demo step has an
# offline backup.
glob llm: Model = Model(model_name="gemini/gemini-2.5-flash");


# ══════════════════════════════════════════════════════════════════════
#  SURVEYOR -- no AI. The senses.
# ══════════════════════════════════════════════════════════════════════

"""A fingerprint of everything an operator would notice changing."""
def grid_signature(base: Base) -> str {
    parts: list[str] = [
        f"islands={base.island_count}",
        f"dark={base.dark_loads}",
        f"alert={base.weather_alert}"
    ];
    for a in sorted(assets_of(base), key=asset_label) {
        state = "up" if a.alive else "DOWN";
        if isinstance(a, GridTie) and not (a as GridTie).live {
            state = "OPEN";
        }
        if isinstance(a, Load) and (a as Load).shed {
            state = "shed";
        }
        parts.append(f"{asset_label(a)}:{state}");
    }
    return "|".join(parts);
}


"""Human-readable diff between two signatures."""
def describe_change(before: str, after: str) -> str {
    old = dict([(p.split(":")[0], p) for p in before.split("|") if ":" in p]);
    changes: list[str] = [];
    for p in after.split("|") {
        if ":" not in p {
            continue;
        }
        k = p.split(":")[0];
        if old.get(k, p) != p {
            changes.append(f"{k} {old.get(k, '')} -> {p.split(':')[1]}");
        }
    }
    return "; ".join(changes) if changes else "state changed";
}


walker Surveyor {
    """Each cycle: read the weather off the graph, act on it, notice change."""

    has new_incidents: list[Incident] = [];

    can sense with Base entry {
        # A live NWS alert is a real signal, not a simulated one. Charging the
        # batteries BEFORE the storm arrives is the one preventative action the
        # system takes, and it is a plain rule, not a model call.
        if here.weather_alert and not here.storm_prep {
            here.storm_prep = True;
            self.new_incidents.append(log_incident(
                "storm_warning",
                here.weather_headline,
                here.survival_hours,
                ["STORM PREP: charging all batteries at maximum rate while the "
                 "utility tie is still available"]
            ));
        }
        if not here.weather_alert and here.storm_prep {
            here.storm_prep = False;
        }

        # Fuel exhaustion is worth an incident even though islanding handles
        # it with no special case.
        for a in assets_of(here) {
            if isinstance(a, Genset) and a.alive and (a as Genset).fuel_liters <= 0.0 {
                a.alive = False;
                self.new_incidents.append(log_incident(
                    "fuel_exhausted",
                    f"{asset_label(a)} is out of fuel and has dropped offline",
                    here.survival_hours,
                    [f"{asset_label(a)} removed from the source set"]
                ));
            }
        }

        sig = grid_signature(here);
        if here.last_signature != "" and sig != here.last_signature {
            self.new_incidents.append(log_incident(
                "state_change",
                describe_change(here.last_signature, sig),
                here.survival_hours,
                []
            ));
        }
        here.last_signature = sig;
    }
}


# ══════════════════════════════════════════════════════════════════════
#  CHRONICLER -- AI. The writer.
# ══════════════════════════════════════════════════════════════════════

obj SitRep {
    has summary: str = "";
    has actions_taken: list[str] = [];
    has survival_assessment: str = "";
    has recommendation: str = "";
}

sem SitRep.summary = "Two or three plain sentences on what failed and how the "
    "system responded, in the register of a military energy-resilience "
    "incident report. Name the actual assets. State no diagnosis you were not "
    "given.";
sem SitRep.actions_taken = "Each automatic action, restated in plain English, "
    "one per entry. Do not invent actions that are not in the input list.";
sem SitRep.survival_assessment = "One sentence on whether the 72-hour mission "
    "endurance target is met, using the number provided.";
sem SitRep.recommendation = "One concrete next action for the base commander. "
    "Specific and physical, e.g. dispatch fuel, inspect a breaker.";

sem write_sitrep = "Write an incident report for a military microgrid "
    "controller. You are given decisions that have ALREADY been made by a "
    "deterministic control loop. Your job is to explain them, not to "
    "second-guess them and not to add new ones.";
sem write_sitrep.kind = "The incident category, e.g. line_loss or asset_loss.";
sem write_sitrep.detail = "What happened, as recorded by the sensors.";
sem write_sitrep.islands = "A one-line summary of each electrical island.";
sem write_sitrep.shed_loads = "The buildings the controller de-energised.";
sem write_sitrep.survival_hours = "Projected hours of endurance for the "
    "weakest island carrying load.";
def write_sitrep(
    kind: str,
    detail: str,
    islands: str,
    shed_loads: list[str],
    survival_hours: float
) -> SitRep by llm(temperature=0.2);


"""A one-line-per-island summary -- the only grid state CHRONICLER ever sees."""
def islands_brief(islands: list[IslandEnergy]) -> str {
    lines: list[str] = [];
    for e in islands {
        mode = "grid-tied" if e.grid_tie else "islanded";
        hrs = ">168" if e.survival_hours >= (HORIZON_H as float)
              else f"{e.survival_hours:.1f}";
        lines.append(
            f"island {e.island_id} ({mode}): {e.load_kw:.0f} kW live of "
            f"{e.total_load_kw:.0f} kW, {hrs} h endurance"
        );
    }
    return " | ".join(lines);
}


"""Deterministic report used when there is no API key or the model errors.

Not a stub: it is the offline backup for the demo, and it is built from the
same brain outputs the model would have received.
"""
def fallback_sitrep(
    kind: str, detail: str, islands: str, shed: list[str], hours: float
) -> SitRep {
    ok = hours >= SURVIVAL_TARGET_H;
    verdict = "meets" if ok else "does NOT meet";
    return SitRep(
        summary=f"[offline report] {kind}: {detail}. The controller "
                f"re-computed islanding and load priority. {islands}.",
        actions_taken=[f"de-energised {n}" for n in shed] if shed
                      else ["no load shedding was required"],
        survival_assessment=f"Projected endurance {hours:.1f} h, which "
                            f"{verdict} the 72-hour target.",
        recommendation="Confirm the fault location and stage fuel resupply."
                       if not ok else
                       "Hold current configuration and monitor the weakest island."
    );
}


"""Have CHRONICLER write up an incident, and persist the result on the graph.

The report is stored on the Incident node, so it survives a restart with no
save code -- persistence is reachability from root.
"""
def chronicle(inc: Incident, islands: list[IslandEnergy], hours: float) -> Incident {
    shed: list[str] = [];
    for e in islands {
        shed += e.shed_names;
    }
    shed = sorted(shed);
    brief = islands_brief(islands);
    rep = fallback_sitrep(inc.kind, inc.detail, brief, shed, hours);
    try {
        rep = write_sitrep(inc.kind, inc.detail, brief, shed, hours);
        inc.authored_by = "CHRONICLER (gemini-2.5-flash)";
    } except Exception {
        inc.authored_by = "CHRONICLER (offline template)";
    }
    inc.report = rep.summary;
    inc.actions = rep.actions_taken + [rep.survival_assessment];
    inc.recommendation = rep.recommendation;
    inc.survival_hours = hours;
    return inc;
}


# ══════════════════════════════════════════════════════════════════════
#  RED -- AI. The attacker. This is the "is it really an agent?" proof.
# ══════════════════════════════════════════════════════════════════════

obj AttackPlan {
    has target: str = "";
    has reasoning: str = "";
    has predicted_survival_hours: float = 0.0;
    has runner_up: str = "";
    has mitigation: str = "";
}

sem AttackPlan.target = "The exact asset label to disable, copied verbatim "
    "from list_targets. Must be one of those strings.";
sem AttackPlan.reasoning = "Two or three sentences on why this target does "
    "more damage than the alternatives. Cite what probe_endurance returned.";
sem AttackPlan.predicted_survival_hours = "The endurance in hours that "
    "probe_endurance reported for the chosen target.";
sem AttackPlan.runner_up = "The second-best target you considered.";
sem AttackPlan.mitigation = "The one change the defender should make to blunt "
    "this attack.";

sem RedPlanner = "An adversary planning a physical attack on a military "
    "microgrid, in the style of CISA advisory AA24-038A. You have read-only "
    "tools. Use list_targets to see what exists, get_tier_map to see what the "
    "defender considers critical, and probe_endurance on SEVERAL candidates "
    "before committing -- the lowest resulting endurance, or the most dark "
    "tier-1 load, is the best target.";


obj RedPlanner {
    has objective: str = "maximise loss of tier-1 mission load and drive "
                         "projected endurance below the 72-hour target";

    # --- the tools. All three are READ-ONLY graph lookups. ---

    def list_targets() -> list[str] {
        base = find_base();
        if base is None {
            return [];
        }
        out: list[str] = [];
        for a in sorted(assets_of(base), key=asset_label) {
            k = asset_kind(a);
            if k == "gridtie" or k == "solar" or k == "battery"
               or k == "genset" or k == "feeder" {
                out.append(f"{k} :: {asset_label(a)}");
            }
        }
        return out;
    }

    def get_tier_map() -> list[str] {
        base = find_base();
        if base is None {
            return [];
        }
        out: list[str] = [];
        for a in sorted(assets_of(base), key=asset_label) {
            if isinstance(a, Load) {
                l = a as Load;
                out.append(f"tier{l.tier} :: {l.name} :: {l.demand_kw:.0f} kW");
            }
        }
        return out;
    }

    # A counterfactual, not an attack: kill the asset, ask the DETERMINISTIC
    # brain what happens, then put everything back exactly as it was. RED is
    # reasoning against the same control loop that will have to survive it.
    def probe_endurance(target: str) -> str {
        found = find_base();
        if found is None {
            return "no grid available";
        }
        grid = found as Base;
        # Never probe something that is already offline: the restore step at
        # the end would turn it back on and hand the defender a free repair.
        if is_down(grid, target) {
            return f"target={target} is already offline - probing it changes nothing";
        }
        if not kill_asset(grid, target) {
            return f"unknown target '{target}' - use a label from list_targets";
        }
        _ = grid spawn RunTriage();
        dark_t1 = len([
            a for a in assets_of(grid)
            if isinstance(a, Load) and a.island_id == -1 and (a as Load).tier == 1
        ]);
        shed_n = len([
            a for a in assets_of(grid)
            if isinstance(a, Load) and (a as Load).shed
        ]);
        hrs = grid.survival_hours;
        out = (f"target={target} endurance={hrs:.1f}h "
               f"islands={grid.island_count} dark_loads={grid.dark_loads} "
               f"dark_tier1={dark_t1} loads_shed={shed_n}");
        # undo -- a probe must never leave the real grid changed
        _ = restore_asset(grid, target);
        clear_shedding(grid);
        _ = grid spawn RunTriage();
        return out;
    }

    def plan() -> AttackPlan by llm(
        tools=[self.list_targets, self.get_tier_map, self.probe_endurance],
        temperature=0.3,
        max_react_iterations=8
    );
}


"""Exhaustive-search attacker used when there is no API key.

It probes every candidate and picks the worst outcome. Slower to explain on
stage than RED's reasoning, but it is the offline backup -- and it is also
the ground truth RED's answer gets compared against.
"""
def red_bruteforce() -> AttackPlan {
    planner = RedPlanner();
    best = "";
    best_score = -1.0;
    runner = "";
    best_hours = 0.0;
    for entry in planner.list_targets() {
        label = entry.split(" :: ")[-1];
        probe = planner.probe_endurance(label);
        if "already offline" in probe {
            continue;
        }
        hours = 999.0;
        dark_t1 = 0.0;
        for field in probe.split(" ") {
            if field.startswith("endurance=") {
                hours = float(field.split("=")[1].replace("h", ""));
            }
            if field.startswith("dark_tier1=") {
                dark_t1 = float(field.split("=")[1]);
            }
        }
        # Dark tier-1 load dominates; endurance loss is the tiebreak.
        score = dark_t1 * 1000.0 + (1000.0 - min(hours, 1000.0));
        if score > best_score {
            best_score = score;
            runner = best;
            best = label;
            best_hours = hours;
        }
    }
    if best == "" {
        return AttackPlan(target="", reasoning="no reachable targets");
    }
    final = planner.probe_endurance(best);
    return AttackPlan(
        target=best,
        reasoning="[offline search] Probed every disableable asset with the "
                  f"defender's own control loop. {best} produced the worst "
                  f"outcome: {final}",
        predicted_survival_hours=best_hours,
        runner_up=runner,
        mitigation=f"Add a redundant source to the island that depends on {best}."
    );
}


walker RedAgent {
    """Plan an attack, then execute it through the ordinary kill switch.

    RED gets NO special powers. It flips exactly the boolean an operator's
    mouse click flips, and the brain responds to it the same way it responds
    to a storm. A storm, a hacker and a mouse click are all just 'an edge went
    dead' -- that symmetry is the point.
    """

    has execute: bool = True;
    has plan: AttackPlan = AttackPlan();
    has authored_by: str = "";

    can attack with Base entry {
        planner = RedPlanner();
        try {
            self.plan = planner.plan();
            self.authored_by = "RED (gemini-2.5-flash, ReAct + graph tools)";
        } except Exception {
            self.plan = red_bruteforce();
            self.authored_by = "RED (offline exhaustive search)";
        }
        if self.plan.target == "" {
            return;
        }
        if self.execute {
            _ = kill_asset(here, self.plan.target);
        }
    }
}

sem RedPlanner.objective = "What the adversary is trying to achieve.";
sem RedPlanner.list_targets = "Every asset that can be disabled, by exact "
    "label. Returns strings of the form 'kind :: label'.";
sem RedPlanner.get_tier_map = "Every building with its criticality tier and "
    "demand. Tier 1 is what the defender will never voluntarily turn off.";
sem RedPlanner.probe_endurance = "Simulate disabling one asset and report the "
    "consequences without actually attacking. Pass an exact label from "
    "list_targets. Returns projected endurance hours, island count, how many "
    "loads go dark, and how many the defender has to shed.";
sem RedPlanner.probe_endurance.target = "Exact asset label to test.";
sem RedPlanner.plan = "Investigate the grid with your tools, then commit to a "
    "single target and justify it.";
