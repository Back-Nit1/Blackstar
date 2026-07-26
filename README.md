# BLACKSTART

**A self-healing power grid for a military base or hospital, written in Jac.**

When the city power line dies — storm, equipment failure, or a hacker — BLACKSTART
answers three questions in the same second:

1. **Who still has power?** Which buildings can still reach a working source.
2. **How long will it last?** Stored energy vs. burn rate, integrated against the
   *real* hourly solar forecast.
3. **What do we turn off to survive longer?** Kill the gym and the A/C before you
   ever touch the ICU, the radar, or comms.

The control loop is fully deterministic and contains **zero model calls**. AI sits
strictly on top of it: explaining, imagining, and attacking — never deciding.

> ### What is real and what is not
> Grid **layout**, building names and per-building demand are a labelled
> **digital twin** — a real installation's single-line diagram is not public.
> The **generation mix** is modelled on published figures for JFTB Los Alamitos.
> **Weather, weather alerts and the solar curve are real, live, public data**,
> fetched from `api.weather.gov` and the Open-Meteo forecast API at
> 33.79, −118.05. This distinction is printed in the UI and by the CLI.

---

## Quick start

Requires Python 3.11+ and Node 18+ (Bun is auto-installed by `jac start`).

```bash
cd blackstart

# one time
python3 -m venv ../.venv
source ../.venv/bin/activate
pip install jaclang byllm jac-client
```

Then, one command at a time:

```bash
jac script sim          # scripted scenario + determinism proof   (~6 s)
jac script invariants   # the 11-test invariant suite            (~16 s)
jac script web          # the web app  →  http://localhost:8000
jac script data         # refresh the live weather/solar cache
```

`jac script web` does **not** return to your prompt — it stays running and
streams logs. Open a second terminal tab for anything else; `Ctrl+C` stops it.

<details>
<summary>Without activating the venv</summary>

```bash
../.venv/bin/jac run sim.jac --profile headless
../.venv/bin/jac test invariants.jac --profile headless
../.venv/bin/jac start --dev main.jac
```

`jac script` shells out to a bare `jac`, so it needs the venv on `PATH`.
The `--profile headless` flag is what the scripts add for you — see below.
</details>

### Why `--profile headless` matters

`sim.jac` and the invariant tests both call `rebuild_twin()`, which wipes and
rebuilds the graph. If they share the served graph while `jac start` is running,
the two processes race for the same SQLite anchors and the CLI dies on exit with
`WriteConflict: anchor ... changed concurrently`. The `headless` profile in
`jac.toml` points them at their own session file:

```toml
[environments.headless.run]
session = ".jac/headless.session"
```

With it, you can run the sim and the tests while the web app is serving and
neither notices the other.

### Optional: refresh the live data

```bash
python3 glue/fetch_live_data.py
```

Hits two free, keyless public APIs and writes `data/live_feed.json` — 24 hours of
real irradiance (W/m²) plus the current National Weather Service alert for the
site. **The simulation only ever reads the cached file, never the network**, so
dead conference wifi cannot stall a tick. A committed copy is already in `data/`.

### Optional: turn on the AI agents

```bash
export GEMINI_API_KEY=...        # or GOOGLE_API_KEY
```

CHRONICLER and RED both degrade to deterministic offline implementations if no
key is present, so nothing hard-fails without one — but the reports are written
by a template instead of a model, and every incident is bylined honestly with
which one produced it.

---

## Verified behaviour

### The headless run (`jac run sim.jac`)

```
  site      JFTB Los Alamitos (digital twin)   (33.79, -118.05)
  weather   Heat Advisory issued July 26 ... by NWS San Diego CA
  data      solar: Open-Meteo forecast API (live) | alerts: api.weather.gov (live)

T+0  nominal — city power up
  islands 1   SURVIVAL >168.0 h

T+1  the city tie opens
      SHED tier-3 Fitness Center (-180 kW)
      SHED tier-3 Exterior Lighting (-90 kW)
      SHED tier-3 Barracks A HVAC (-300 kW)
      SHED tier-3 Sports Field Lighting (-70 kW)
  islands 3   SURVIVAL 74.4 h vs 72 h target -> INTACT

T+2  BESS-1 destroyed
      SHED tier-3 Barracks B HVAC (-260 kW)
  SURVIVAL 75.2 h -> INTACT

T+3  city power restored
      RESTORE tier-3 ... (all five)
  islands 1   SURVIVAL >168.0 h

DETERMINISM CHECK — same scenario, second run
  PASS  13 decisions, identical on both runs.
```

It never sheds a tier-1 load (medical, comms, radar, water, dispatch), and never
sheds tier 2 while a tier-3 load in the same island is still running.

### The RED agent

Turned loose on an already-islanded grid, RED probes every disableable asset with
the defender's own control loop and picks **`FDR-A Mission`** — the feeder
carrying the Medical Clinic and Comms & Network Ops:

```
RED target : FDR-A Mission
runner-up  : BESS-1
reasoning  : Probed every disableable asset with the defender's own control loop.
             FDR-A Mission produced the worst outcome: endurance=11.0h islands=4
             dark_loads=5 dark_tier1=2 loads_shed=7
```

After the attack: **5 loads dark, 2 of them tier 1, survival collapses to 10.9 h.**
Note what the controller does *not* do — it still refuses to shed a tier-1 load
and reports the honest 10.9 h instead. Tier-1 buildings went dark because they
were physically disconnected, which is a different thing from being shed, and
the UI shows them differently (red, labelled `DARK`).

---

## Architecture

```
  messy world                deterministic core                 AI layer
  ───────────                ──────────────────                 ────────
  weather.gov     ┐
  Open-Meteo      ├─ glue/ ─► the GRAPH ─► triage.jac ─► verdict ─► agents.jac
  operator click  │           (grid.jac)   physics.jac              (explains,
  RED agent       ┘                        ops.jac                   imagines,
                                                                     attacks)
                                              │
                                           api.jac  ─► frontend.cl.jac
                                       (walkers = REST)   (the same language)
```

### The one rule that governs everything

> **The brain decides. The AI only explains, imagines, and attacks.**

If an LLM ever picked which building to shed, the system would stop being
predictable, and predictability is the entire safety story. `triage.jac`,
`physics.jac` and `ops.jac` contain no `byllm` import — and that is asserted by
a test, not promised in a README:

```jac
test "the deterministic core contains no model calls" {
    for name in ["triage.jac", "physics.jac", "ops.jac"] {
        src = source_of(name);
        assert "import from byllm" not in src;
        assert "by llm(" not in src;
        assert "Model(" not in src;
    }
}
```

### The grid *is* the database

No ORM, no schema migration, no tables. A power line is an `edge`, a building is
a `node`, and anything reachable from `root` persists between runs for free.

```jac
edge Feeds: GridNode --> GridNode { has live: bool = True; }
```

Cutting power is flipping one boolean on one edge. A storm, a mouse click, and
the RED attacker agent all go through **the same** function (`ops.kill_asset`) —
RED gets no special powers.

### Islanding is a walker, not a BFS you maintain

```jac
walker IslandWalker {
    has island_id: int;
    can mark with GridNode entry {
        if not here.alive { skip; }
        if here.island_id != -1 { skip; }
        if isinstance(here, GridTie) and not (here as GridTie).live { skip; }
        here.island_id = self.island_id;
        visit [here ->:Feeds:live == True:->];
        visit [here <-:Feeds:live == True:<-];
    }
}
```

In any other stack this is "keep an adjacency list, hand-write a BFS, keep it in
sync with the DB." Here **the grid is the adjacency list and the walker is the
BFS**. A cut edge simply isn't in the query result, so islands appear with no
special-case code anywhere. About 30 nodes, so we recompute from scratch every
cycle — no caching, no incremental invalidation, no bugs.

The `GridTie` guard is what makes the demo work: an open utility breaker is a
hard electrical boundary, so killing the city tie *splits* the base into separate
islands instead of merely removing a source.

### One engineering detail worth the whole demo

The 31 MW utility-scale PV plant sits on the **utility side of the point of common
coupling**. When the city tie opens it drops out with the grid — it is not
islandable. Only the smaller behind-the-meter arrays (2.8 MW) stay with the base.
That is why losing the city tie hurts far more than "we still have 31 MW of
panels" suggests, and it is the most common misconception about military
microgrids. You can watch it happen: island count goes to 3 and one of those
islands is 31 MW of stranded generation with zero load.

### The survival clock integrates a real forecast

`stored_kWh / load_kW` is meaningless on a solar microgrid — the same island is
comfortable at noon and starving at 2 a.m. `triage.project_endurance` steps the
**real hourly irradiance curve** forward one hour at a time, draining storage,
and reports the hour the lights go out (capped at 168 h).

Dispatch order inside each hour is fixed, and `physics.jac` uses the identical
order — if the projection and the simulation disagreed, the clock would be a lie:

1. **Solar** — free, use every watt.
2. **Generator, up to its power rating** — the only source with a large energy
   reserve behind it.
3. **Battery** — covers what the generator's rating can't, and absorbs surplus
   solar during the day.

The intuitive ordering ("battery first, fuel is precious") is wrong, and it cost
us four extra shed buildings before we caught it: draining the battery first
strands the entire fuel tank behind the genset's kW rating, so the instant the
battery empties, an island whose load exceeds genset rating is declared dead
while sitting on 120 MWh of diesel. You conserve fuel by **shedding load**, not
by idling the machine that carries base load.

### Load shedding: tiers, total ordering, hysteresis

The 3-tier split is a direct copy of the **NFPA 99** hospital branch model, so a
facilities engineer reads it without translation:

| Tier | Meaning | Examples in the twin |
|---|---|---|
| 1 | Never shed | Medical clinic, comms, radar/ATC, water & wastewater, emergency dispatch |
| 2 | Shed only if desperate | Ops & admin HQ, hangar, fuel farm pumps, vehicle maintenance, dining |
| 3 | Shed first | Fitness center, barracks HVAC, exterior/sports lighting, wash rack |

- Shed order is a **total** ordering: `(-tier, priority, name)`, alphabetical
  tiebreak. No randomness, no dict order, no wall-clock read.
- Restore order is `(tier, -priority, name)` — tier 2 comes back before tier 3.
- **Hysteresis:** the target is 72 h, but a load is only restored above **84 h**
  (`TARGET + MARGIN`). Without that dead-band a load sitting on the line flips on
  and off every tick as solar wiggles. Real energy-management systems do the same.
- Tier 1 is never a candidate. If only tier 1 remains and the target is still
  missed, the system reports the honest lower number.

### Why 72 hours

Japan sized its post-2011 community microgrids for roughly three days of
autonomous operation. It's a real resilience target, not a number picked to look
good.

### Units

kW, kWh, liters, hours — everywhere, no exceptions. Half of all energy bugs are
unit mix-ups. Diesel converts at `liters / burn_lph × rated_kw` → kWh.

---

## The AI layer

| Agent | AI? | What it does |
|---|---|---|
| **SURVEYOR** | no | The senses. Reads the live NWS alert off the graph, raises `storm_prep` (pre-charging batteries while the tie is still up), notices fuel exhaustion, and diffs a grid signature to log every state change. |
| **CHRONICLER** | `by llm()` | Writes the plain-English incident report. Its inputs are the **brain's outputs** — a one-line-per-island brief and the shed list — never raw state, so it has nothing to hallucinate about. Result is stored on the `Incident` node and persists for free. |
| **RED** | `by llm(tools=[...])` | The attacker, modelled on CISA advisory **AA24-038A** (Volt Typhoon). Three read-only graph tools: `list_targets`, `get_tier_map`, `probe_endurance`. It has to *plan* — probe several candidates, compare, commit — then it kills through the ordinary `kill_asset` path. |

`probe_endurance` is the interesting one: RED runs a genuine counterfactual
against the defender's own deterministic control loop, then unwinds it. It
refuses to probe an already-dead asset, because the unwind would otherwise hand
the defender a free repair.

Every AI call is wrapped so that a missing key or a model error falls back to a
deterministic implementation, and the incident is bylined with which one ran.

---

## File map

```
blackstart/
├── grid.jac              the data model — every node + edge archetype
├── triage.jac            the brain: islanding, endurance, shedding    (NO AI)
├── physics.jac           the clock: 15-min ticks, dispatch, fuel burn (NO AI)
├── ops.jac               operator actions + persistent incident log   (NO AI)
├── seed.jac              builds the digital twin, ingests live data
├── agents.jac            SURVEYOR, CHRONICLER, RED
├── api.jac               walker:pub endpoints — the whole REST layer
├── sim.jac               headless runner + determinism proof
├── invariants.jac        11 tests that make the safety claims real
├── main.jac              entry point: server imports + the cl { } block
├── frontend.cl.jac       the operator screen
├── frontend.impl.jac     its handler bodies
├── components/
│   ├── GridMap.cl.jac    the clickable SVG grid
│   └── Panels.cl.jac     island cards + incident feed
├── styles/global.css     styling  (note: NOT .styles -- see below)
├── glue/                 the only Python: one 57-line fetcher, no logic
└── data/                 cached live feed (the offline backup)
```

> **Gotcha we hit:** `import ".styles.global.css";` in `main.jac` compiles to
> `./styles/global.css` — the *leading* dot is the relative-path marker and the
> rest are path separators. Putting the file in a hidden `.styles/` directory
> gives you `[plugin:vite:import-analysis] Failed to resolve import` and a blank
> page. The directory is `styles/`.

**Jac vs Python: 2,882 lines of Jac to 57 lines of Python — about 98% Jac.**
The Python does nothing but `urlopen` two public APIs and write JSON. Every
decision — including how irradiance converts to PV output — lives in Jac.

There is no `.js`, `.jsx`, `.ts` or `.tsx` file in this repo. The browser UI,
the REST API, the simulation and the tests are one language and one type checker.

---

## API

Every `walker:pub` is automatically `POST /walker/<Name>` (API on :8001 in dev).

| Endpoint | Body | Returns |
|---|---|---|
| `GetSnapshot` | `{}` | the whole grid: nodes with positions, edges, islands, weather |
| `Tick` | `{"steps": 24}` | advance 15 min per step, then re-survey |
| `KillAsset` | `{"label": "BESS-1"}` | kill, re-plan, write the incident report |
| `RestoreAsset` | `{"label": "BESS-1"}` | restore and let the brain bring load back |
| `GetIncidents` | `{"limit": 12}` | the log with CHRONICLER's reports |
| `RunRed` | `{"execute": true}` | RED plans and attacks |
| `ResetGrid` | `{}` | rebuild the twin from seed |

---

## Known limits

- Single base. `jac start --scale` would run a fleet on the same code, but that
  is untested here.
- ORACLE (the "what if we'd shed tier 2 first?" counterfactual narrator) is
  specified but not built. `RedPlanner.probe_endurance` already does the
  mechanical half of it.
- The endurance projection assumes today's solar curve repeats. Over a 168-hour
  horizon that is an approximation, and it is stated as one.
- Auto-run (ticking on a timer) is deliberately not in the UI — the demo is
  click-driven and a timer is one more thing to fail on stage.
