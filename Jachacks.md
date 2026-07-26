# **BLACKSTART — Build Plan for Claude Code**

### **JacHacks SF · one-day build · 10:45 AM – 7:15 PM PT**

Build like a systems engineer: the least code that works, kept simple and reliable.

---

## **0\. First, two rules about the language**

We're building in **Jac**, a new language. Two things matter before you write a single line:

**Rule 1 — Don't guess Jac's syntax.** Jac is new and changes often, so it's easy to write syntax that doesn't exist. Before writing any `.jac` file, go read the real docs and keep them open:

* `https://docs.jaseci.org/learn/tools/llmdocs/` → grab **`llmdocs-jaseci-mini_v3.txt`**, that's your syntax bible.  
* `https://docs.jaseci.org/reference/` → the sections on Object-Spatial Programming, byLLM, and jac-scale.  
* If this doc ever disagrees with the live docs, **the docs win.** Match the current syntax and leave a one-line comment saying you did.

**Rule 2 — Write Jac like Jac, not Python-in-disguise.** We're judged mainly on *how well we use Jac*, and **at least 40% of the code must be Jac** (hard rule — miss it and we're disqualified). Every design choice below exists *because* Jac has a feature that makes it natural. If you catch yourself writing a normal Python class with a graph bolted on the side, stop — you've drifted.

> *Python is allowed only for tiny "go fetch this from the internet" helper scripts. No real logic, no decisions, no data living in Python. If a Python file passes \~50 lines, something's wrong.*

---

## **1\. What we're building (the plain version)**

**BLACKSTART is a self-healing power grid for a military base or hospital.**

Picture a base's electricity: the city power line coming in, solar panels, batteries, a diesel generator, and a bunch of buildings drawing power. Now something breaks — a storm knocks out a line, or a hacker kills the city connection. BLACKSTART instantly figures out three things:

1. **Who still has power?** (which buildings can still reach a working power source)  
2. **How long will it last?** (stored energy ÷ how fast we're using it \= hours left)  
3. **What do we turn off to survive longer?** (kill the gym and A/C before you ever touch the ICU or the radar)

Then, on top of that, a few AI helpers **explain what happened, reason about "what if," and even play the attacker.**

> *Technically: we model the grid as a live graph, run a deterministic control loop (islanding → endurance → tiered load-shedding), and layer LLM agents on top for narration, counterfactuals, and adversarial planning. The control loop never calls an LLM.*

**Why these specific numbers?** So nothing looks made up:

* Real military microgrids are public: **JFTB Los Alamitos** has \~31 MW of solar, a 20–40 MWh battery, 3 MW of diesel, and can run alone for 14+ days. We copy those real numbers.  
* Hospitals legally sort power into **"never turn off" vs "turn off if you must"** (that's the NFPA 99 code). Our 3-tier system is a direct copy of that, so an expert judge recognizes it.  
* **72 hours of survival** is a real target (Japan built community microgrids after the 2011 disaster sized for \~3 days alone). That's our big number on screen.  
* We can't get a real base's internal wiring (it's secret, obviously). So the **grid layout is a labeled "digital twin"** — but everything it *reacts to* (weather, solar output, real outages) is **live real data.** We say this out loud in the UI. Lying about what's real is a disqualification here.  
  ---

  ## **2\. The demo we're building toward**

This is the finish line. **If a feature doesn't help this 90-second story, don't build it.**

1. Screen shows the base grid, a live weather banner, and survival clocks.  
2. A real weather alert pops up → the **SURVEYOR** agent charges the batteries early ("storm prep").  
3. You **click the city power line to kill it** → the grid visibly splits into islands, the gym/A/C dim off, the survival clock recalculates → **"72 hrs: INTACT."**  
4. You **kill a battery** → the system re-plans, and the **CHRONICLER** agent writes a plain-English incident report explaining every move it made.  
5. *(Stretch)* The **RED** attacker agent says which part it would sabotage next for maximum damage — and the system hardens against it.  
   ---

   ## **3\. Why Jac makes this easy (read before coding)**

This is the heart of the project. Each Jac feature below maps to one design decision. Judges will poke at exactly this, so the code has to make each claim true.

**Plain English first, then the technical version:**

**a) The grid IS the database.** In Jac you declare "nodes" and "edges" and they *are* your data — no separate database, no tables. So a power line is literally an edge with an on/off switch, and the base's wiring diagram becomes the code directly. Killing power \= flipping one switch on one edge.

> *Jargon: graph-native data model. `node`/`edge` archetypes, `++>` to connect, typed edges with `has` attributes. A `Feeds` edge with `live: bool` is a breaker.*

**b) Saving happens automatically.** Anything connected to the built-in starting point stays saved between runs, for free. We write zero database code — the whole grid, its history, and the incident log just persist.

> *Jargon: persistence \= reachability from `root`. No ORM, no migrations. Call it out in the README — it deletes a whole infrastructure layer.*

**c) The "workers" move to the data.** Jac has "walkers" — little pieces of logic that travel across the graph and do a job wherever they land. Our whole islanding algorithm is just "a walker walks along the live power lines and marks everything it can reach." The algorithm and the graph-walk are the same thing. Our AI agents are walkers too, so "the agents live inside the grid" is literally true.

> *Jargon: walkers \= mobile computation dispatched by arrival. `spawn`, `visit`, `here`, abilities like `can act with NodeType entry`.*

**d) "Find all connected X" is one line, not a loop.** Jac lets you query the graph directly — "all live neighbors downstream" is a single expression, not a hand-written loop. Use this style everywhere; it's the idiom judges look for.

> *Jargon: typed edge-filtered queries, e.g. `[node ->:Feeds:live == True:->]` and `(?Load)` type filters.*

**e) The AI is a language feature, not a bolted-on API.** In Jac you write a function with a *type* but no body, tag it "done by the LLM," and Jac handles the prompt for you. So "write an incident report" becomes a normal typed function that happens to be filled in by an AI — no prompt strings, no JSON parsing. This is the single most-rewarded feature at this event.

> *Jargon: `by llm()` \+ `sem` annotations. Structured input/output objects. ReAct mode with a tool list for agents that need to look things up while thinking.*

**f) Our functions become a web API for free.** Every walker automatically becomes a web endpoint — no Flask, no FastAPI, no routes to write. The frontend just calls them.

> *Jargon: walkers auto-expose via `jac serve` / jac-scale.*

**g) Laptop today, whole fleet tomorrow — same code.** The exact same program runs one base on your laptop or 130 bases across a cluster. That's a real pitch line, not marketing.

> *Jargon: `jac start` → `jac start --scale`.*

**The one rule that ties it together:** if you want to store state, put it *on the graph* (not a Python dict). If you want to loop over neighbors, *query the edges* instead. If you want to write a prompt, make it a `by llm()` function instead.

---

## **4\. The files**

blackstart/  
├── main.jac         \# start everything: build the grid, run the loop, serve it  
├── grid.jac         \# the data model (all nodes \+ edges)  
├── physics.jac      \# the clock: batteries drain/charge, generators burn fuel  
├── triage.jac       \# the brain (NO AI here): islanding, survival math, shedding  
├── agents.jac       \# the AI helpers: SURVEYOR, CHRONICLER, ORACLE, RED  
├── seed.jac         \# builds the fake-but-realistic base from real public numbers  
├── glue/            \# tiny Python fetchers (weather, solar) — no logic  
├── data/            \# one pre-downloaded real storm/outage file  
├── frontend/        \# the visual grid (see §8)  
└── README.md        \# architecture \+ the "what's real vs simulated" label

---

## **5\. The data model (`grid.jac`)**

**Plain version:** we're writing down every part of the grid — power sources, buildings, and the wires between them — as graph nodes and edges. Each building gets a **tier**: 1 \= never turn off (ICU, radar, comms), 2 \= turn off only if desperate, 3 \= turn off first (gym, A/C, outdoor lights).

Keep the comments in the code — judges read the repo.

* \# ── Power sources & storage ───────────────────────────────────────  
* \# Each one holds exactly the numbers the survival math needs (§6).  
* \# Units are always kW / kWh / liters. Never mix them.  
*   
* node GridTie {                 \# the city power line coming in  
*     has utility: str;  
*     has live: bool \= True;     \# is city power present? THIS is the main kill switch  
*     has capacity\_kw: float;  
* }  
*   
* node Solar {  
*     has name: str;  
*     has capacity\_kw: float;    \# panel size (real Los Alamitos ≈ 31,000 kW)  
*     has output\_kw: float \= 0.0;\# how much it's actually making right now (from weather)  
* }  
*   
* node Battery {  
*     has name: str;  
*     has capacity\_kwh: float;   \# real: 20,000–40,000 kWh  
*     has soc\_kwh: float;        \# current charge; physics.jac updates this each tick  
*     has max\_discharge\_kw: float;  
* }  
*   
* node Genset {                  \# diesel generator  
*     has name: str;  
*     has rated\_kw: float;  
*     has fuel\_liters: float;  
*     has burn\_lph: float;       \# liters burned per hour at full power  
* }  
*   
* \# ── Buildings & wiring ────────────────────────────────────────────  
*   
* node Feeder { has feeder\_id: str; }   \# a branch line off the main bus  
*   
* node Load {                    \# a building / thing that uses power  
*     has name: str;  
*     has demand\_kw: float;      \# how much it draws (from real building profiles)  
*     has tier: int;             \# 1 \= never shed, 2 \= shed if desperate, 3 \= shed first  
*     has shed: bool \= False;    \# currently turned off?  
*     has island\_id: int \= \-1;   \# which island it's in; \-1 means it's dark (no power)  
* }  
*   
* node Base {  
*     has name: str;  
*     has lat: float;  has lon: float;  
*     has survival\_hours: float \= 0.0;   \# the big number on screen  
* }  
*   
* node IncidentLog {}            \# things that happen hang off this and get saved  
* node Incident {  
*     has ts: str;  
*     has kind: str;             \# "line\_loss" | "asset\_loss" | "storm\_warning" | ...  
*     has detail: str;  
*     has report: str \= "";      \# CHRONICLER writes the plain-English report here  
* }  
*   
* \# ── The wires ─────────────────────────────────────────────────────  
* \# \`Feeds\` is the power line. live \== False means it's cut.  
* \# Cutting power \= flipping this one boolean. Islands appear automatically  
* \# when a walker only follows the live ones. That's the whole trick.  
*   
* edge Feeds  { has live: bool \= True; }  
* edge PartOf {}                 \# "this belongs to that" (Base ⊃ Feeder ⊃ assets)  
* edge Logged {}                 \# IncidentLog → Incident  
*   
*   
* \# ── The wires ─────────────────────────────────────────────────────  
* \# \`Feeds\` is the power line. live \== False means it's cut.  
* \# Cutting power \= flipping this one boolean. Islands appear automatically  
* \# when a walker only follows the live ones. That's the whole trick.  
*   
* edge Feeds  { has live: bool \= True; }  
* edge PartOf {}                 \# "this belongs to that" (Base ⊃ Feeder ⊃ assets)  
* edge Logged {}                 \# IncidentLog → Incident


**What `seed.jac` builds:** one base (a "Los Alamitos twin," real coords 33.79, \-118.05), three feeder branches, the real generation mix (31 MW solar, a 30 MWh battery starting half-full, a 3 MW generator with 72 hours of fuel), the city tie, and \~12–18 buildings across the three tiers with believable names (Tier 1: comms, radar, medical; Tier 2: fuel pumps, ops/admin; Tier 3: barracks A/C, gym, exterior lights). Draw demand numbers from the free DOE building-energy CSVs (hospital, office, warehouse). Wire it `GridTie → Feeder → building`, with sources feeding into their feeder. **Three feeders is on purpose** — killing one line causes a *partial* blackout, which demos better than all-or-nothing.

> *Because saving \= being connected to root, building this graph once means the twin survives restarts with no save code.*

---

## **6\. The brain (`triage.jac`) — no AI allowed in this file**

**Plain version:** this is the part that actually decides what to do, and it must give the **exact same answer every time** for the same situation. That matters because (a) real grid software has to be predictable, (b) it's what makes us different from "an AI guesses what to turn off," and (c) a judge can test it live by doing the same thing twice. Keep AI completely out of here.

### **6a. Finding the islands (who still has power)**

**Plain:** start at each working power source and walk outward along only the *live* wires, tagging every building you reach. Anything you never reach is dark.

> *An `IslandWalker` spawns at each viable source, visits only live `Feeds` edges (use the edge-filtered query, not a manual loop), and stamps `island_id` on each `Load`. Unreached loads stay at `-1`. \~30 nodes total, so just recompute from scratch every cycle — no caching, no clever incremental updates. Simple \= correct here.* *Why it's the Jac showcase: elsewhere this is "keep an adjacency list, write BFS, keep it synced with the DB." Here the grid **is** the adjacency list and the walker **is** the BFS. Put that sentence in the README.*

### **6b. The survival clock**

**Plain:** for each island, add up the stored energy, subtract what solar is giving you for free, and divide by how fast you're burning power. That's your hours left.

* stored\_kwh   \= sum of battery charge \+ generator fuel converted to kWh  
* net\_load\_kw  \= power used by everything still on  −  free solar right now  
* survival\_hours \= stored\_kwh / net\_load\_kw  
* 


> *Write `survival_hours` onto the `Base` node so the frontend reads it from the graph, not from a response payload. Floor `net_load_kw` at a tiny ε so you never divide by zero. Show it against the 72-hour target.*

### **6c. Turning things off to survive (shedding)**

**Plain:** if you won't make it 72 hours, start turning off the least-important stuff (tier 3), then tier 2 if you're still short. **Never turn off tier 1** — if only tier 1 is left and you still won't make 72 hours, just report the honest lower number. And once you're comfortably back above target, turn things back on — but wait until you're *well* above the line so nothing flickers on and off.

TARGET \= 72 hours;  MARGIN \= 12 hours

if survival \< TARGET:  turn off tier-3 first, then tier-2, recheck after each. Never tier-1.

turn back on only when survival \> TARGET \+ MARGIN (restore tier-2 before tier-3)

> *That MARGIN gap is hysteresis. Without it, a load sitting right at the line flips on/off every tick as solar wiggles — real energy-management systems handle it the same way. One extra comparison; it's the detail that makes an engineer-judge nod.* *Determinism: always walk loads in a fixed order (tier, then priority, then name). No randomness, no real-world clock inside decisions, no LLM. Tiebreak on name alphabetically.*

### **6d. The clock loop (`physics.jac`)**

**Plain:** every "tick" is 15 simulated minutes. Each tick: update battery charge, burn some generator fuel, refresh solar from the pre-loaded weather data, then re-run the brain (find islands → survival math → shedding), in that order.

> *A `TickWalker` does: battery `soc_kwh += (charge − discharge) × Δt` (clamp 0..capacity); genset `fuel_liters −= burn_lph × utilization × Δt` (at 0 fuel it just stops being a source — islanding notices next cycle, no special case); solar from the pre-fetched curve; then spawn IslandWalker → endurance → ShedWalker. When short on power in an island, use solar first (free), battery next, generator last (fuel is precious) — leave that as a comment.*

---

## **7\. The AI helpers (`agents.jac`)**

**The golden rule, one sentence:** *the brain decides; the AI only explains, imagines, and attacks.* If an AI ever made the shedding decision, the system would stop being predictable — that separation is our whole safety story.

> *Model setup (confirm the exact import against llmdocs — it moves around):*

import from byllm { Model }

glob llm \= Model(model\_name="gemini/gemini-2.5-flash");   \# Gemini

> 

> *Key comes from an environment variable. Never commit it. RED can optionally use a second, NVIDIA-hosted model — only if everything else is done — for the "attackers on NVIDIA, defenders on Gemini" line.*

**SURVEYOR** *(no AI — it's the senses).* Each tick it refreshes solar, checks the latest weather alert, notices anything that changed (a wire died, fuel ran out, an alert fired), and logs an incident. On a real weather alert, it charges batteries early ("storm prep").

**CHRONICLER** *(AI — the writer).* After anything happens, it writes the plain-English incident report. **Notice: its inputs are the brain's outputs** — it never sees raw state and never invents facts, it just turns decisions already made into readable English. Cheap to build, judges love it.

> obj SitRep { has summary: str; has actions\_taken: list\[str\];

>              has survival\_assessment: str; has recommendation: str; }

> def write\_sitrep(kind: str, detail: str, islands: str,

>                  shed\_loads: list\[str\], survival\_hours: float) \-\> SitRep by llm();

> sem SitRep.summary \= "2-3 plain sentences on what failed and how the system responded, styled like a military energy-resilience incident report";

> sem SitRep.recommendation \= "one concrete next action for the base commander";

> 

> *Store the result on `Incident.report` so it persists.*

**ORACLE** *(AI — the "what if," optional).* Answers "what if we'd turned off tier-2 first?" The *code* re-runs the survival math for the alternative; the AI just contrasts the two outcomes in words. Build only if time allows.

**RED** *(AI — the attacker, this is our "real agent" proof).* Modeled on the real **CISA Volt Typhoon** warning (AA24-038A — hackers pre-positioned in US power infrastructure; cite it on the slide). RED has to *plan* — look at the grid, figure out the single most damaging target, and go for it. That planning-under-uncertainty is exactly what the "is it really an agent?" judging criterion wants (they say wrapping one API call doesn't count).

def plan\_attack(objective: str) \-\> AttackPlan by llm(method="ReAct", tools=\[self.list\_targets, self.probe\_endurance, self.get\_tier\_map\]);

> 

> *Its tools are read-only graph lookups. It reasons like "the city tie is backed up across feeders, but battery B2 is the only backup for the tier-1 loads on island 2 → hit B2." Crucially, it kills the target through **the exact same edge-flip the operator's mouse-click uses** — no special powers, and the brain responds the same way. That symmetry (a storm, a hacker, and a mouse click are all just "an edge went dead") is worth a README paragraph. If the ReAct/tools syntax differs in current docs, adapt — the requirement is: AI plans multi-step using graph lookups, brain executes.*

---

## **8\. Getting the real data in (`glue/`)**

**Plain:** small Python scripts grab real weather, real solar output, and one real past storm, and hand them to the graph. Grab them once and store them *on the graph* — so if the venue Wi-Fi dies mid-demo, everything still runs.

| Data | Where | Key needed? | Used for |
| ----- | ----- | ----- | ----- |
| Weather alerts \+ forecast | `api.weather.gov` | no | storm-prep trigger \+ the UI banner |
| Solar output curve | NREL PVWatts v8 (`developer.nrel.gov`) | free key | how much the panels make each tick |
| A real past storm to replay | ORNL EAGLE-I outage CSV (pre-downloaded) | no | "watch us replay a real documented outage" |
| Earthquake trigger | USGS live feed | no | optional extra incident source |

> *Rules: every fetch is cached onto the graph at startup or on a slow (60s+) poll. The tick loop reads only from the graph — a network hiccup must never stall it. Each glue script is just: fetch → parse → hand a plain dict to a walker that writes it onto the graph. Nothing more.*

**Say what's real (required — lying \= disqualification):** put this in the README and visibly in the UI —

> *"Grid layout & sensor readings: a digital twin from public base specs (Los Alamitos, SPIDERS, MCAS Miramar). Weather, solar, and outage history: real, live public data."*

---

## **9\. The screen (`frontend/`)**

**Plain:** one page showing the grid as a map of dots and lines. Islands are color-coded, turned-off buildings are dimmed, dark buildings are red, and each island shows a big survival clock. A weather banner runs across the top. **Click any part to kill it.** That's it — resist the urge to add dashboards.

> *Run it under `jac serve` (walkers become endpoints). The frontend needs only: get a graph snapshot, kill/restore something, get the latest incident+report, trigger RED. Preferred: build the UI in **jac-client** if the docs make it doable in \~90 min (single-file full-stack is a scoring item). Fallback: one static page with a force-graph library (D3 or cytoscape.js) polling once a second. Base44 is an optional cosmetic wrapper at the very end — the real visualization stays in our repo.*

---

## **10\. The schedule**

**M1 · 10:45–12:30 · data model \+ seed \+ islanding.** Passes when: you kill the city tie in the terminal → the island count changes, dark loads show `island_id = -1`, and restoring recovers them. Same result twice.

**M2 · 12:30–2:00 · survival math \+ shedding \+ hysteresis \+ tick loop.** Passes when: you kill the tie → tier-3 turns off in a fixed order, survival reads ≥ 72h; a solar wiggle does NOT cause flicker; and rerunning gives an identical sequence.

**M3 · 2:00–2:45 · the glue (weather \+ solar \+ storm replay).** Passes when: the tick loop runs on the real solar curve, a storm replay creates incidents, and unplugging the network → it still runs on cache.

**M4 · 2:45–4:45 · SURVEYOR \+ CHRONICLER, then RED.** Passes when: an incident produces a saved plain-English report that names the buildings actually shed, and RED names a target with reasoning and kills it the normal way.

**M5 · 4:45–6:15 · the screen \+ demo run-through.** Passes when: the full §2 story runs clean, twice in a row.

**M6 · 5:50 & 6:15–7:10 · submit.** Submit a draft on Devpost at 5:50 (required), write the README, record the 1:30 video, star `github.com/jaseci-labs/jac`, and do the final submit before the 7:15 hard stop. Passes when: it's submitted.

**If you fall behind, cut in this order:** ORACLE first → RED's second model (keep RED on Gemini) → any multi-base stuff → the Base44 wrapper. **Never cut:** the predictable brain (M1–M2), CHRONICLER, the "what's real" label, or the 5:50 checkpoint. *A small grid that heals itself the same way every time beats a big one that trips once on stage.*

## **If you fall behind, cut in this order:** ORACLE first → RED's second model (keep RED on Gemini) → any multi-base stuff → the Base44 wrapper. **Never cut:** the predictable brain (M1–M2), CHRONICLER, the "what's real" label, or the 5:50 checkpoint. *A small grid that heals itself the same way every time beats a big one that trips once on stage.*

---

## **11\. Rules to keep taped to the wall**

1. **At least 40% Jac** — count lines before submitting; keep the Python glue tiny.  
2. **First commit after 10:45 AM** — and commit often; the timeline proves you built it during the event.  
3. **No AI in `triage.jac` or `physics.jac`** — if a `byllm` import shows up there, it's a bug by definition.  
4. **The graph is the only source of truth** — no state hiding in Python variables or files.  
5. **Predictability is testable** — same action twice must give the same result twice.  
6. **One set of units** — kW, kWh, liters, hours. Half of all energy bugs are unit mix-ups.  
7. **Every demo step has an offline backup.**  
8. **When Jac surprises you, re-read llmdocs before improvising.** The live docs are the truth; this plan is just the intent.  
* 

