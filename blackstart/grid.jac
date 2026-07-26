"""BLACKSTART - the campus graph.

Naval Medical Center Portsmouth. It is a hospital, so it has ICUs and operating
rooms. It is also a DoD installation, so 10 U.S.C. 2925 requires it to report
how long its mission survives without power. Same building, two mandates.

The map IS the program. Buildings are nodes. Cables are edges. Not data about a
graph -- the actual graph. Attach it to `root` and it is saved; there is no
database anywhere in this project.

WHAT IS REAL: the facility roster, the building numbers, the bed and operating
room counts, and the 112-acre riverside campus are real and public (Navy
Medicine / NMCP releases). WHAT IS NOT: the single-line diagram. No hospital
publishes its electrical drawings, so the wiring is a labelled twin.

Units are fixed: power kW, energy kWh, fuel liters, time hours.

ONE NAMING RULE, AND IT IS LOAD-BEARING: asset names must carry real-world
meaning that is NOT encoded anywhere in this graph. "Riverside Substation",
"Basement Chiller Plant", "Pier-Side Fuel Farm". RED only ever sees names, so
the names are its sole world-knowledge hook -- it has to know that floods go
downhill, because we never told it. A for-loop sees a string.
"""

# ── The shared base archetype ──────────────────────────────────────────
# Everything physical inherits GridNode, which gives the islanding walker a
# single `with GridNode entry` catch-all and gives every asset the two fields
# the control loop cares about:
#   island_id -- which electrical island it landed in; -1 means dark
#   alive     -- is it intact? A flood, a mouse click and RED all flip this
#                one boolean, through the same function.
node GridNode {
    has island_id: int = -1;
    has alive: bool = True;
}


# ── Sources and distribution ───────────────────────────────────────────

node UtilityTie(GridNode) {
    """The commercial feed. `live` is the main breaker."""

    has utility: str = "";
    has capacity_kw: float = 0.0;
    has live: bool = True;
}

node Substation(GridNode) {
    """A campus substation. The name says where it sits; the graph does not."""

    has name: str = "";
    has capacity_kw: float = 0.0;
}

node Feeder(GridNode) {
    """A branch circuit off a substation."""

    has feeder_id: str = "";
}

node TieSwitch(GridNode) {
    """A normally-closed bus tie. Opening one splits two feeders apart."""

    has name: str = "";
}

node Generator(GridNode) {
    """Diesel. Burns fuel in proportion to what it delivers, not to runtime.

    Fuel lives in two places, which is how real plants are built and which is
    what makes the road matter: a small day tank at the machine, and a bulk
    tank the truck fills. If the supply route is cut, only the day tank counts
    -- typically a few hours, not a few days.
    """

    has name: str = "";
    has rated_kw: float = 0.0;
    has fuel_liters: float = 0.0;   # day tank
    has bulk_liters: float = 0.0;   # reachable only while the route is open
    has burn_lph: float = 1.0;      # liters per hour at rated output
    has output_kw: float = 0.0;
}

node Battery(GridNode) {
    """UPS / central battery. Rides through, then it is gone."""

    has name: str = "";
    has capacity_kwh: float = 0.0;
    has soc_kwh: float = 0.0;
    has max_discharge_kw: float = 0.0;
}

node SupplyRoute(GridNode) {
    """The road the fuel truck uses.

    This node is why the flood -> road -> truck -> dry generator chain is
    mechanical rather than narrated. It carries no power. Kill it and the
    generators cannot be refuelled, which the endurance math notices only
    later -- exactly like the real thing.
    """

    has name: str = "";
    has serves: str = "";
}


# ── The things that need power ─────────────────────────────────────────

node Facility(GridNode) {
    """A department or building.

    `tier` is the NFPA 99 essential-electrical-system split, unchanged:
        1 = life safety / critical branch -- never shed
        2 = equipment branch -- shed only when desperate
        3 = normal power -- shed first
    """

    has name: str = "";
    has building: str = "";
    has demand_kw: float = 0.0;
    has tier: int = 3;
    has shed: bool = False;
    # Total ordering inside a tier so BLUE is replayable. Lower sheds first.
    # Ties break alphabetically on name -- never dict order, never random.
    has priority: int = 50;
}

node Campus(GridNode) {
    """The site. The screen reads its state straight off this node."""

    has name: str = "";
    has lat: float = 0.0;
    has lon: float = 0.0;
    has hours_left: float = 0.0;      # the one number on screen
    has target_hours: float = 96.0;
    has island_count: int = 0;
    has dark_facilities: int = 0;
    has dark_tier1: int = 0;
    has generation_kw: float = 0.0;
    has lit_load_kw: float = 0.0;
    has tick: int = 0;
    has provenance: str = "";
}


# ── The audit chain ────────────────────────────────────────────────────
# "Why did the third floor go dark at 2:03?" is a three-week SCADA archaeology
# project today. Here it is a graph walk, because every decision is a node with
# an edge pointing at the evidence that caused it. Nothing is reconstructed
# after the fact -- it is recorded as it happens and it persists for free.

node Snapshot(GridNode) {
    """The state of the campus at one tick. Chained to the previous one."""

    has tick: int = 0;
    has islands: int = 0;
    has hours_left: float = 0.0;
    has generation_kw: float = 0.0;
    has lit_load_kw: float = 0.0;
    has dark_tier1: int = 0;
}

node Event(GridNode) {
    """Something happened TO the grid: a cut, a flood, a RED strike."""

    has tick: int = 0;
    has kind: str = "";          # cut | restore | red_strike | fuel_out | miss
    has target: str = "";
    has detail: str = "";
    has actor: str = "operator"; # operator | RED | physics
}

node Decision(GridNode) {
    """Something the controller decided to DO. Always carries its evidence."""

    has tick: int = 0;
    has action: str = "";        # SHED | RESTORE
    has subject: str = "";
    has tier: int = 0;
    has rule: str = "";
    has rationale: str = "";
}


# ── RED's memory ───────────────────────────────────────────────────────
# Persisted on the graph like everything else, so a lesson learned in round 1
# is still there in round 4 and survives a restart with no save code.

node RedRound(GridNode) {
    has round: int = 0;
    has narrative: str = "";
    has strikes: list[str] = [];
    has misses: list[str] = [];
    has lesson: str = "";
    has try_next: str = "";
    has dark_tier1: int = 0;
    has min_hours: float = 0.0;
    has memory_on: bool = True;
    has authored_by: str = "";
}


# ── The wires ──────────────────────────────────────────────────────────
# `Feeds` is the cable. live == False means it is cut. We never wrote a
# splitting algorithm: the islanding walker only follows live cables, so a cut
# cable simply is not in the query result and the islands appear by themselves.

edge Feeds: GridNode --> GridNode {
    has live: bool = True;
}

edge PartOf: GridNode --> Campus {}          # every asset belongs to the site
edge Serves: SupplyRoute --> Generator {}    # the road that reaches the bulk tank

# --- audit chain edges ---
edge Follows: Snapshot --> Snapshot {}       # newer --> older
edge Observed: Snapshot --> Event {}         # what this tick saw
edge Because: Decision --> Snapshot {}       # the evidence for a decision
edge Triggered: Event --> Decision {}        # the event that forced it
edge Affected: Decision --> Facility {}      # who it happened to

edge Logged: Campus --> RedRound {}          # RED's memory
