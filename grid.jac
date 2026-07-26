"""BLACKSTART - the grid data model.

The grid IS the database. Every physical asset is a graph node, every power
line is a graph edge. There is no ORM, no table, no migration: anything
reachable from `root` persists between runs for free.

Units are fixed everywhere in this project:
    power   -> kW
    energy  -> kWh
    fuel    -> liters
    time    -> hours
Half of all energy bugs are unit mix-ups, so we never mix them.
"""

# ── The shared base archetype ──────────────────────────────────────────
# Every physical asset inherits GridNode. That gives the islanding walker a
# single `with GridNode entry` catch-all (a walker's bare `with entry` only
# fires at the spawn node, never on later visits), and it gives every asset
# the two fields the control loop cares about:
#   island_id -- which electrical island it ended up in; -1 means dark
#   alive     -- is the asset itself intact? A storm, a mouse click and RED
#                all take an asset out by flipping this one boolean.
node GridNode {
    has island_id: int = -1;
    has alive: bool = True;
}

# ── Power sources & storage ────────────────────────────────────────────
# Each one holds exactly the numbers the survival math needs (triage.jac).

node GridTie(GridNode) {
    """The city power line coming in. `live` is the main kill switch."""

    has utility: str = "";
    has capacity_kw: float = 0.0;
    has live: bool = True;
}

node Solar(GridNode) {
    """A PV array. output_kw comes from the real hourly solar curve."""

    has name: str = "";
    has capacity_kw: float = 0.0;
    has output_kw: float = 0.0;
}

node Battery(GridNode) {
    """Storage. physics.jac moves soc_kwh every tick; it never jumps."""

    has name: str = "";
    has capacity_kwh: float = 0.0;
    has soc_kwh: float = 0.0;
    has max_discharge_kw: float = 0.0;
    has max_charge_kw: float = 5000.0;
}

node Genset(GridNode) {
    """Diesel generator. Burns fuel only in proportion to what it delivers."""

    has name: str = "";
    has rated_kw: float = 0.0;
    has fuel_liters: float = 0.0;
    has burn_lph: float = 1.0;
    has output_kw: float = 0.0;
}

# ── Buildings & wiring ─────────────────────────────────────────────────

node Feeder(GridNode) {
    """A branch line off the main bus. Three of them, on purpose: killing one
    line causes a partial blackout, which demos better than all-or-nothing."""

    has feeder_id: str = "";
}

node Load(GridNode) {
    """A building. `tier` is a direct copy of the NFPA 99 hospital split:
    1 = life safety / mission critical, never shed
    2 = shed only if desperate
    3 = shed first
    """

    has name: str = "";
    has demand_kw: float = 0.0;
    has tier: int = 3;
    has shed: bool = False;
    # Deterministic shed order inside a tier. Lower priority sheds first.
    # Ties break alphabetically on name -- never on dict order, never random.
    has priority: int = 50;
}

node Base(GridNode) {
    """The installation itself. The frontend reads its state straight off this
    node -- the graph is the only source of truth, not a response payload."""

    has name: str = "";
    has lat: float = 0.0;
    has lon: float = 0.0;
    has survival_hours: float = 0.0;
    has island_count: int = 0;
    has dark_loads: int = 0;
    has sim_hour: float = 18.0;      # hour-of-day in the simulation clock
    has tick_count: int = 0;
    # 24 hourly fractions (0..1) of solar nameplate, from real PVWatts data.
    has solar_curve: list[float] = [];
    has solar_scale: float = 1.0;    # storm derate applied to the curve
    has weather_headline: str = "no data";
    has weather_alert: bool = False;
    has storm_prep: bool = False;
    has data_provenance: str = "";
    # SURVEYOR's memory of the last state it saw, so it can notice change.
    # It lives on the graph like everything else -- never in a Python dict.
    has last_signature: str = "";
}

node IncidentLog(GridNode) {
    """Everything that happens hangs off this and is saved automatically."""

    has count: int = 0;
}

node Incident(GridNode) {
    has ts: str = "";
    has kind: str = "";
    has detail: str = "";
    has report: str = "";            # CHRONICLER writes plain English here
    has actions: list[str] = [];
    has recommendation: str = "";
    has survival_hours: float = 0.0;
    has authored_by: str = "system";
}

# ── The wires ──────────────────────────────────────────────────────────
# `Feeds` is the power line. live == False means it is cut.
# Cutting power = flipping this one boolean. Islands appear automatically
# because the islanding walker only follows the live ones. That is the
# whole trick -- there is no separate adjacency list to keep in sync.

edge Feeds: GridNode --> GridNode {
    has live: bool = True;
}

edge PartOf: GridNode --> GridNode {}      # Base > Feeder > asset

edge Logged: IncidentLog --> Incident {}
