BLACKSTART — the pitch  
Say it like this.  
---

The problem (20 seconds)  
A hospital loses power.  
It has backup generators and batteries. Not enough for everything. Something has to be turned off.  
Who? A priority list an engineer wrote when the building opened. It has never changed.  
And afterward, when someone asks "why did the third floor go dark at 2:03?" — nobody can answer. They spend three weeks digging through logs, guessing.  
---

What we built (20 seconds)  
A live map of the hospital's power.  
Cut a cable — the map splits into pieces. Pieces with a generator stay lit. Pieces without are on batteries, counting down.  
One number on screen: hours of power left.  
When it drops too low, the least important thing goes off. And every decision gets written down, so you can always ask why.  
---

How it works

1. Load a real hospital power grid — buildings, cables, generators  
2. Something breaks  
3. The map splits into islands  
4. Each island counts its hours left  
5. reprioritization  
6. Write down what happened and why

That's it.  
---

Where the AI is  
One place. It decides what breaks next.  
Not randomly. Real failures happen in chains:  
Flood hits the low substation. The road floods too. The fuel truck can't get through. The generator that was fine runs dry.  
Our map doesn't know any of that. It knows cables and kilowatts. It doesn't know that floods go downhill, or that trucks need roads.  
The AI knows. So the AI writes the scenario.  
And it remembers. Round 1 it cuts the main feed — we survive on the backup route. Round 2 it cuts the backup route first, then the feed. Now the split happens wrong and the ICU is stranded.  
That move is not in our code. It learned it.  
Where the AI is NOT  
Deciding who loses power. That's a list and a loop, on purpose.  
"Nobody is going to let a language model decide who loses power in a hospital. The intelligence goes on the threat, because you can't script what goes wrong."  
Say that. It sounds like a weakness. It's the opposite.  
---

Where Jac is  
1\. The map is the program. Buildings are nodes. Cables are edges. Not data about a graph — the actual graph.  
2\. Splitting happens by itself. We tell our code: only walk cables that are live. Cut one, and it can't get across. We never wrote a splitting algorithm.  
3\. No database. In Jac, attach something to root and it's saved. Our entire decision history is just there.  
4\. The AI call is a function with no body. We write what goes in and what comes out. Jac fills in the middle. There is no prompt anywhere in our code.  
---

The demo — 4 minutes  
① Show the map.  
"This is a real power grid from a national lab. Real cables, real switches."  
② Break it. Cut a cable. The map splits on screen.  
"We never wrote that. In Jac you can't walk down a cut cable, so the splitting just happens."  
③ Watch the number. 41 hours. Target is 96\. Cafeteria goes dark.  
"That's the rule doing its job. Boring on purpose."  
④ Round 2\. The AI goes again — and cuts the backup route first. The split happens wrong. ICU stranded. Number collapses.  
"We didn't write that move. It read what happened in round one."  
Point at the screen where its notes are.  
⑤ Ask why.  
"Why did the cafeteria go dark?"  
Walk it back:  
"Substation 3 opened at tick 47\. East wing lost its path to the generators. Generation dropped from 400 to 180 kilowatts. Hours left fell to 41, under the 96 target. Rule says shed tier 3\. Cafeteria is tier 3."  
"Hospitals spend three weeks reconstructing that from logs."  
⑥ Reload as a military base.  
"Same code. Federal law requires every base to report how many hours its mission can survive without power. Nothing computes it live. This does."  
---

The two sentences to memorize  
"The defense is a dumb checklist on purpose. The intelligence is on what goes wrong, because you can't script a disaster."  
"The grid doesn't just survive the failure. It can tell you why."  
---

If a judge pushes back  
"Isn't that just a priority list?"  
"Yes — and it should be. That part is solved. What's not solved is knowing what to plan for, and being able to explain what happened. That's what we built."  
"Why do you need an LLM?"  
"To pick a cable, we don't — a loop does that better. We need it to write a sequence that makes sense in the real world. Floods go downhill. Trucks need roads. That's not in our data."  
"Does the memory actually help?"  
"Here's the same run with memory turned off." \[show both counters\]  
 The LLM is the only part of your system that knows things that aren't in your data.  
Your graph knows nodes, edges, kilowatts. It does not know:

* that hurricanes flood low elevation first, so those substations fail together  
* that fuel trucks need passable roads  
* that a surgical suite matters more when there's an operation in progress  
* that operators trust displays

None of that is in SMART-DS. None of it is in any dataset you can download. It's world knowledge, and generating a plausible failure sequence requires it. A for-loop over your edges will happily produce sequences that no real hurricane would ever cause.  
That's the defensible line: "The simulation knows physics. The model knows context. You need both to generate a scenario worth planning against."  
"Blue is too weak."  
Your team is right, and you have two honest options.  
Option A — accept it and make it a virtue. Blue is a tier table because that's what's accreditable. Say it proudly, and the whole pitch becomes "we put intelligence exactly where it belongs and nowhere else." Clean, but Blue stays boring.  
Option B — make Blue's job reconfiguration, not shedding. Shedding is a sorted list. Rewiring isn't. Which tie switches to close, in what order, to re-form islands so that critical load lands on the generation you still have — that's combinatorial search over topology, and it's genuinely hard. It's also what FLISR does in the real world, so it's not invented.

**BLUE is 20 lines and you stop touching it.** A while loop that sheds the lowest tier until endurance clears target. Build it by 12:45, never open the file again.

**RED is four steps per round: LOOK → PLAN → RUN → REFLECT.** Two LLM calls, and REFLECT is the one teams skip. Without it there's no memory and you're back to a for-loop.

**The single most important decision is what RED can see.** Give it the *dashboard* — facility names, lit/dark status, hours left, island count. Not the cable list. If RED can see which cable connects to what, a loop can enumerate it and your whole argument dies. If it only sees names and status, it has to guess how things connect — which is also what a real attacker faces, since they know the buildings but not the electrical drawings.

That's why RED names `"North Substation"` rather than `edge_7`, and your code resolves it.

**Two things that will bite you:**

Run the A/B by 3:15, not 5:00. If memory doesn't beat no-memory, the likely cause is your graph being too small — on 12 nodes round one gives away the whole structure and there's nothing left to learn. Fix by growing to 20–30 nodes or hiding more from the dashboard. You need hours for that, not minutes.

Two calls. That's it.

**Call 1 — PLAN.** Every round, RED looks at the dashboard and decides what breaks next.

can plan(view: Dashboard, lessons: list\[Lesson\]) \-\> Scenario by llm();

**Call 2 — REFLECT.** After it plays out, RED writes down what it learned.

can reflect(scenario: Scenario, outcome: Outcome) \-\> Lesson by llm();

Everything else in the system is arithmetic.

---

**Why PLAN needs a model:** because failures come in chains that only make sense if you know things about the world.

> Flood hits the low substation → the road floods → the fuel truck can't get through → the generator that was fine runs dry.

Your graph knows cables and kilowatts. It does not know that floods go downhill or that trucks need roads. **A for-loop would cut a random cable.** The model writes a sequence a real hurricane would actually produce.

**Why REFLECT is the one that matters:** it's the difference between an agent and a search.

If round 1 hands round 2 a number — `damage: 340` — that's hill-climbing and you don't need AI. If it hands over a *sentence* —

> *"Cutting the main feed didn't work. Three islands formed, so there's a backup route I didn't know about. Take that out first next time."*

— there's no variable that holds it. Round 2's move exists because of that sentence.

**Most teams build PLAN and skip REFLECT.** Then they have an LLM picking from a list, which is exactly what the judging criteria call "wrapping an API call." REFLECT is what makes it a loop instead of a lookup.

---

**The part that makes it hard to enumerate:** RED sees the *dashboard*, not the graph. Facility names, lit or dark, hours left. Not the cable list. So it can't enumerate — it has to form a theory about how things connect and test it.

**The part where AI is absent, on purpose:** deciding who loses power. That's BLUE, and BLUE is a while loop. Say that out loud — *"nobody lets a language model decide who loses power in a hospital"* — because it's the sentence that makes a judge trust the rest.

**And the Jac angle:** look at those two functions again. No prompt anywhere. Just a signature, a docstring, and no body. Jac generates the rest. Put that on screen.

Datasets \+ Startup Framing  
---

🎯 THE FINDING: build a military hospital

You've been agonizing over hospital-vs-defense. **Stop. They're the same building.**

HIFLD's hospital dataset categorizes facilities as \<cite index="26-1"\>children, chronic disease, critical access, general acute care, long term care, **military**, psychiatric, rehabilitation, special, and women.\</cite\>

Military hospitals are real, named, and public:

| Facility | Where | Why it's good |
| ----- | ----- | ----- |
| **Naval Medical Center Portsmouth** | Norfolk, VA | Hurricane exposure, ties to your naval work, PJM grid |
| Walter Reed (WRNMMC) | Bethesda, MD | Most recognizable name in military medicine |
| Naval Medical Center San Diego | San Diego, CA | Local-ish to SF judges |
| Tripler Army Medical Center | Honolulu, HI | Island grid — genuinely isolated |

**Why this solves everything:**

* **Social Impact** — it's a hospital. ICU, surgery, ventilators. No strain.  
* **AI for Defense** — it's a DoD installation. §2925 applies. No strain.  
* **One demo.** No reload, no "this also works for." **It IS both.** That's what dual-use actually means.  
* **Legible to Salesforce/Apple/Google judges** — everyone understands a hospital losing power.  
* **Credible to the Initium judge** — it's a real military medical facility with a real resilience mandate.

> *"Naval Medical Center Portsmouth. It's a hospital, so it has ICUs and operating rooms. It's also a military installation, so federal law requires it to report how long its mission survives without power. Same building, two mandates, one system."*

**Pick Portsmouth.** Hurricane country, naval, and you already have Norfolk-area data.

---

The datasets — final list  
Download tonight (all local, no demo-time network)

| \# | Source | What | Where |
| ----- | ----- | ----- | ----- |
| **1** | **SMART-DS** (NREL) | The graph. Real feeder in GeoJSON — cables, switches, protection devices, 15-min loads | `data.openei.org/submissions/2981` |
| **2** | **EAGLE-I** (ORNL) | Real outage records, county-level, 15-min | `osti.gov/biblio/1975202` |
| **3** | **HIFLD Hospitals** | Facility locations \+ the `military` category | See caveat below |
| **4** | **MIRTA** | DoD installation boundaries | `catalog.data.gov/dataset/military-installations-ranges-and-training-areas` |

⚠️ **HIFLD access has changed.** \<cite index="31-1"\>HIFLD Secure now requires a GII account, a profile, and an approved Data Use Agreement.\</cite\> The **open** layers are still reachable through mirrors — \<cite index="26-1"\>the Data Rescue Project portal hosts HIFLD Open Hospitals\</cite\>, and NASA's NCCS keeps a public feature service with hospitals, urgent care, and VHA medical facilities. **Verify your link tonight and save the file.** Do not plan to fetch this at 11 AM.

Skip

Weather, AIS, EIA, PVWatts, ComStock standalone. SMART-DS already carries load profiles, and live weather doesn't change in four minutes.

---

Startup framing — what to say to a YC-minded judge  
The landscape (know this, it's 30 seconds of credibility)

\<cite index="36-1"\>There are 138 microgrid startups; 69 funded, 43 at Series A+.\</cite\> The space is crowded — **in hardware and control.**

Two YC companies are your nearest neighbors, and knowing them makes you sound like a founder rather than a hackathon team:

* **Gridware** (YC, SF Bay Area) — \<cite index="41-1"\>builds smart sensors that help utility companies immediately detect, find, and fix outages.\</cite\> **Hardware. Detection.** They tell you the pole broke.  
* **Squid** (YC) — \<cite index="38-1"\>AI-powered grid planning in the browser, on the thesis that better decisions come from one unified, trusted network model, so that assumptions are visible instead of lost in spreadsheets and static reports.\</cite\> **Planning new infrastructure.**

Where you sit

> *"Gridware tells you the pole broke. Squid helps you plan what to build. Neither one tells a hospital which wing to keep alive at 2 AM, or explains the decision afterward. That's the gap."*

The business — say this, it's what separates you

Both your customers have a **legal requirement that recurs and is done by hand today:**

| Customer | Mandate | Done how today |
| ----- | ----- | ----- |
| Military installation | 10 U.S.C. §2925 — report outage duration, mission impact, and *the downtime the mission can afford* | By hand, weeks later, from logs |
| Hospital | CMS emergency preparedness rule — documented plan, tested, reviewed | By hand, consultants |

> *"This isn't a nice-to-have dashboard. Both customers are legally required to produce this report, both do it by hand, and both do it every year. That's a compliance wedge, and compliance wedges are how infrastructure software gets bought."*

**Wedge → expand:** start as the report generator (mandatory, budgeted, low-risk). Expand into the resilience planning and the live control layer once you're already inside.

The adversarial angle has funding behind it

DOE funded \<cite index="43-1"\>$2.5M for the Midwest Center for Microgrid Cybersecurity to develop and demonstrate new tools for microgrid cyber resilience and corrective actions\</cite\> — with Argonne, IIT, UIC, and ComEd.

So: *"Red-teaming microgrids is a funded federal research area. We built a working version in eight hours."*

---

What won at JacHacks before

| Winner | What it was | Pattern |
| ----- | ----- | ----- |
| **Sentinel** | \<cite index="116-1"\>Multi-agent fraud investigation for Medicare claims — cited case files, evidence, recommended actions, graph-based reasoning\</cite\> | Graph \+ agents \+ **cited evidence** |
| **CivicMesh** | \<cite index="116-1"\>Helped people in crisis navigate housing, food, healthcare, legal aid, and government programs in any language\</cite\> | Civic \+ crisis \+ real-world stakes |
| **Ori** (Best Use of Jac) | \<cite index="116-1"\>Agentic environment where cars talk to each other for safer, more efficient operation\</cite\> | Agents coordinating in a **physical** system |
| **Inocula** (Best Startup Idea, Winter) | Attack/defense over a trust graph | **Adversarial** \+ graph |

The pattern is unmistakable

**Graph \+ agents \+ cited evidence \+ real-world/civic domain.** All four winners. BLACKSTART sits directly in it:

* Graph ✅ — the power network  
* Agents ✅ — RED's plan/reflect loop  
* **Cited evidence ✅** — the snapshot chain is Sentinel's exact shape, pointed at outages  
* Civic/physical ✅ — a hospital losing power  
* **Adversarial ✅** — Inocula proved this wins here

What to steal specifically

**From Sentinel:** the *cited* part. Sentinel didn't just produce an answer, it produced an answer with case files attached. Your incident report must show, per line, which snapshot node it came from. That's the difference between "the AI wrote a summary" and "here's the evidence."

**From Ori:** agents in a *physical* system, not a chat window. Yours is a power grid. Lean into the physicality — the map, the cascade, things going dark.

**From Inocula:** attack/defense is a proven winner at this event. Don't hide RED. Lead with it.

---

The 30-second startup pitch

> *"Every hospital and every military base is legally required to report how long it can survive without power, and what it would shut off to get there. Today that's a human reading SCADA logs for three weeks.*

> *We made the grid a graph. An agent attacks it, learns from what survived, and attacks smarter. A deterministic controller decides who stays lit — no AI there, nobody accredits a language model to shed a hospital's ICU. And every decision is a node you can walk back to.*

> *Gridware tells you the pole broke. We tell you which wing to save, and why."*

---

Tonight — updated

* \[ \] ⭐ Star `github.com/jaseci-labs/jac`  
* \[ \] SMART-DS feeder (GeoJSON)  
* \[ \] EAGLE-I — Norfolk/Portsmouth county, one storm  
* \[ \] **HIFLD Hospitals — verify the mirror link works, save the file**  
* \[ \] Look up Naval Medical Center Portsmouth — buildings, rough layout  
* \[ \] Sleep

