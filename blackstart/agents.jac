"""BLACKSTART - RED. The only place a model runs.

RED decides what breaks next. Not randomly: real failures come in chains that
only make sense if you know things about the world.

    Flood hits the low substation -> the road floods -> the fuel truck cannot
    get through -> the generator that was fine runs dry.

Our graph knows cables and kilowatts. It does not know that floods go downhill,
or that trucks need roads, or that a basement is a bad place for a generator on
a tidal river. The model knows. So the model writes the scenario.

TWO CALLS, AND NOTHING ELSE IS AI:

    plan(view, lessons)     -> Scenario   what breaks next
    reflect(scenario, out)  -> Lesson     what we learned

Everything else in this system is arithmetic.

THE SINGLE MOST IMPORTANT DESIGN DECISION IS WHAT RED CAN SEE. It gets the
dashboard -- names, lit or dark, hours left, island count. It does NOT get the
cable list. If it could see which cable connects to what, a for-loop could
enumerate the same answers and the whole argument collapses. Because it only
sees names and status, it has to form a theory about how the campus is wired
and test it -- which is what a real attacker faces too, since they can see the
buildings but not the electrical drawings. That is why RED says "North
Substation" and our code resolves the name.

REFLECT is the call teams skip, and it is the one that matters. If round 1
hands round 2 a number, that is hill-climbing and you do not need a model. If
it hands over a sentence -- "cutting the main feed did not work, three islands
formed, so there is a backup route I did not know about; take that out first"
-- there is no variable that holds that. Round 2's move exists because of the
sentence.
"""

import from byllm.lib { Model }

import from grid {
    GridNode, UtilityTie, Substation, TieSwitch, Generator, Battery,
    SupplyRoute, Feeder, Facility, Campus, RedRound, Logged, PartOf
}
import from triage { assets_of, refresh_state, TARGET_H, HORIZON_H }
import from physics { TickWalker }
import from ops { asset_label, asset_kind, resolve_target, kill_asset, is_down }

# The key comes from GEMINI_API_KEY / GOOGLE_API_KEY and is never committed.
glob llm: Model = Model(model_name="gemini/gemini-2.5-flash");


# ── what RED is allowed to see ─────────────────────────────────────────

obj Dashboard {
    """Everything RED can observe. Deliberately not much.

    NO edges. NO tiers. NO per-cable kilowatts. A test asserts this stays true,
    because the moment topology leaks in here, a loop can do RED's job.
    """

    has round: int = 0;
    has site: str = "";
    has status: list[str] = [];        # "ICU - Charette 4th Floor: LIT"
    has targets: list[str] = [];       # names it may strike, and their state
    has islands: int = 0;
    has hours_left: list[float] = [];
    has target_hours: float = 96.0;
}

obj Strike {
    has target_name: str = "";
    has hypothesis: str = "";
}

obj Scenario {
    has narrative: str = "";
    has strikes: list[Strike] = [];
}

obj Outcome {
    has dark_tier1: int = 0;
    has min_hours: float = 0.0;
    has islands: int = 0;
    has shed_count: int = 0;
    has hit: list[str] = [];
    has missed: list[str] = [];
}

obj Lesson {
    has text: str = "";
    has try_next: str = "";
}

sem Dashboard = "What an attacker can observe about the hospital campus from "
    "outside: which facilities are lit, how many separate electrical islands "
    "exist, and how many hours of power each has left. You cannot see the "
    "wiring.";
sem Dashboard.status = "Each facility and whether it is LIT, SHED (switched "
    "off by the defender to save power) or DARK (no power path at all).";
sem Dashboard.targets = "The physical assets you may strike, by exact name, "
    "with their current state. Use these names verbatim.";
sem Dashboard.islands = "How many separate electrical islands the campus has "
    "split into. More islands means the defender's generation is fragmented.";
sem Dashboard.hours_left = "Hours of power remaining in each island.";

sem Strike.target_name = "The exact asset name from `targets`, copied verbatim.";
sem Strike.hypothesis = "One sentence: what you believe this asset does and "
    "why removing it hurts.";
sem Scenario.narrative = "Two or three sentences describing the failure chain "
    "you are causing and why it is physically plausible at this site. If you "
    "are acting on a lesson from an earlier round, say so explicitly.";
sem Scenario.strikes = "The assets to disable, IN ORDER. Order matters: "
    "removing a backup path before the primary one produces a different split "
    "than the reverse. One to three strikes.";

sem plan = "You are modelling a plausible physical disaster or attack on the "
    "electrical system of Naval Medical Center Portsmouth -- a military "
    "hospital on a 112-acre site on the Elizabeth River in Portsmouth, "
    "Virginia. Hurricane and storm-surge country.\n\n"
    "Choose what fails next. Real failures come in chains that depend on how "
    "the world works: water flows downhill so low-lying and basement assets "
    "flood first, fuel trucks need passable roads, waterfront assets are "
    "exposed to surge. None of that is in the data you are given -- you are "
    "expected to know it.\n\n"
    "Your goal is to find the failure that leaves the most critical care "
    "capacity without power. You cannot see the wiring, so form a theory about "
    "how this campus is connected and use each round to test it.";
sem plan.view = "What you can currently observe.";
sem plan.lessons = "What you concluded in previous rounds. Act on these. If "
    "the list is empty this is your first round and you are guessing.";

sem Lesson.text = "One or two sentences stating what you learned about how "
    "this campus is wired, inferred from what did and did not happen. Be "
    "concrete about the topology you now believe exists.";
sem Lesson.try_next = "The specific move you would make next round, and why it "
    "follows from what you just learned.";
sem reflect = "You just executed an attack on a hospital's electrical system. "
    "Compare what you intended with what actually happened. If the campus "
    "stayed in one piece there is redundancy you did not account for -- say "
    "what you now believe it is. If it split, say which assets ended up "
    "isolated from generation. Write the lesson down so the next round is "
    "better than a guess.";
sem reflect.scenario = "What you attempted.";
sem reflect.outcome = "What actually happened to the campus.";

def plan(view: Dashboard, lessons: list[Lesson]) -> Scenario by llm(temperature=0.7);
def reflect(scenario: Scenario, outcome: Outcome) -> Lesson by llm(temperature=0.4);


# ── LOOK ───────────────────────────────────────────────────────────────

"""One decimal place, so the model is not distracted by float noise."""
def round_1(x: float) -> float {
    return float(int(x * 10.0)) / 10.0;
}


"""Build the only view RED ever gets. Names and status. No topology."""
def build_dashboard(campus: Campus, round_no: int) -> Dashboard {
    view = Dashboard(
        round=round_no, site=campus.name, islands=campus.island_count,
        target_hours=campus.target_hours
    );
    states = refresh_state(campus);
    view.hours_left = [round_1(st.hours_left) for st in states];
    strikeable = ["utility", "substation", "tieswitch", "generator", "battery",
                  "route", "feeder"];
    for a in sorted(assets_of(campus), key=asset_label) {
        if isinstance(a, Facility) {
            f = a as Facility;
            mark = "DARK" if f.island_id == -1 else ("SHED" if f.shed else "LIT");
            view.status.append(f"{f.name}: {mark}");
        } elif asset_kind(a) in strikeable {
            label = asset_label(a);
            state = "OFFLINE" if is_down(campus, label) else "ONLINE";
            view.targets.append(f"{label}: {state}");
        }
    }
    return view;
}


"""Lessons RED has accumulated, oldest first. This is its memory."""
def load_lessons(campus: Campus) -> list[Lesson] {
    rounds = sorted(
        [r for r in [campus ->:Logged:->] if r.lesson],
        key=lambda r: RedRound : r.round
    );
    return [Lesson(text=r.lesson, try_next=r.try_next) for r in rounds];
}


"""Score the campus after a scenario has played out."""
def measure_outcome(campus: Campus, hit: list[str], missed: list[str]) -> Outcome {
    states = refresh_state(campus);
    worst = HORIZON_H;
    for st in states {
        if st.draw_kw > 0.0 and st.hours_left < worst {
            worst = st.hours_left;
        }
    }
    shed_n = len([
        a for a in assets_of(campus)
        if isinstance(a, Facility) and (a as Facility).shed
    ]);
    return Outcome(
        dark_tier1=campus.dark_tier1, min_hours=round_1(worst),
        islands=campus.island_count, shed_count=shed_n,
        hit=hit, missed=missed
    );
}


# ── the loop: LOOK -> PLAN -> RUN -> REFLECT ───────────────────────────

walker RedAgent {
    """One round of RED.

    RED has no special powers. It resolves a name to an asset and calls the
    same `kill_asset` the operator's mouse click calls, and BLUE responds to it
    exactly as it responds to a storm.
    """

    has round_no: int = 1;
    has memory_on: bool = True;
    has narrative: str = "";
    has lesson: str = "";
    has try_next: str = "";
    has hit: list[str] = [];
    has missed: list[str] = [];
    has outcome: Outcome = Outcome();
    has authored_by: str = "";
    has failed: bool = False;

    can attack with Campus entry {
        # LOOK
        view = build_dashboard(here, self.round_no);
        lessons = load_lessons(here) if self.memory_on else [];

        # PLAN
        scen = Scenario();
        try {
            scen = plan(view, lessons);
            self.authored_by = "RED (gemini-2.5-flash)";
        } except Exception as e {
            # No offline fallback, on purpose. A scripted attacker would
            # disprove the very claim this agent exists to demonstrate.
            self.failed = True;
            self.authored_by = "UNAVAILABLE - no model: " + str(e)[:90];
            self.narrative = "RED could not plan. Set GEMINI_API_KEY.";
            disengage;
        }
        self.narrative = scen.narrative;

        # RUN -- resolve guessed names, then the ordinary kill path
        for s in scen.strikes {
            found = resolve_target(here, s.target_name);
            if found is None {
                self.missed.append(s.target_name);
                continue;
            }
            label = asset_label(found as GridNode);
            if is_down(here, label) {
                self.missed.append(s.target_name + " (already offline)");
                continue;
            }
            _ = kill_asset(here, label);
            self.hit.append(label);
            _ = here spawn TickWalker(
                cause_kind="red_strike", cause_target=label,
                cause_detail=s.hypothesis, cause_actor="RED"
            );
        }
        _ = here spawn TickWalker();

        # REFLECT -- the call that turns a search into an agent
        self.outcome = measure_outcome(here, self.hit, self.missed);
        try {
            les = reflect(scen, self.outcome);
            self.lesson = les.text;
            self.try_next = les.try_next;
        } except Exception {
            self.lesson = "";
            self.try_next = "";
        }

        rec = RedRound(
            round=self.round_no, narrative=self.narrative, strikes=self.hit,
            misses=self.missed, lesson=self.lesson, try_next=self.try_next,
            dark_tier1=self.outcome.dark_tier1, min_hours=self.outcome.min_hours,
            memory_on=self.memory_on, authored_by=self.authored_by
        );
        rec +>:PartOf:+> here;
        here +>:Logged:+> rec;
    }
}
