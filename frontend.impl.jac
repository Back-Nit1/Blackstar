"""Handler bodies for the operator screen.

Every one of these follows the same shape: spawn a walker, take the fresh
Snapshot out of `reports[0]`, assign it. The write-then-refetch pattern is
explicit because a writer call invalidates the client's read cache.
"""

impl app.reloadIncidents -> None {
    log = root spawn GetIncidents(limit=12);
    if log.reports and len(log.reports) > 0 {
        incidents = log.reports[0];
    }
}


impl app.doTick -> None {
    busy = True;
    result = root spawn Tick(steps=1);
    if result.reports and len(result.reports) > 0 {
        snap = result.reports[0];
    }
    await reloadIncidents();
    busy = False;
}


impl app.doTickFast -> None {
    busy = True;
    result = root spawn Tick(steps=24);          # 24 x 15 min = 6 hours
    if result.reports and len(result.reports) > 0 {
        snap = result.reports[0];
    }
    await reloadIncidents();
    busy = False;
}


impl app.doToggle -> None {
    if selected == "" {
        return;
    }
    found = False;
    targetAlive = True;
    current = snap;
    if current is not None {
        for n in current.nodes {
            if n.label == selected {
                found = True;
                targetAlive = n.alive;
            }
        }
    }
    if not found {
        return;
    }
    busy = True;
    # A storm, a mouse click and the RED agent all land on these two walkers.
    if targetAlive {
        killed = root spawn KillAsset(label=selected);
        if killed.reports and len(killed.reports) > 0 {
            snap = killed.reports[0];
        }
    } else {
        restored = root spawn RestoreAsset(label=selected);
        if restored.reports and len(restored.reports) > 0 {
            snap = restored.reports[0];
        }
    }
    await reloadIncidents();
    busy = False;
}


impl app.doRed -> None {
    busy = True;
    plan = root spawn RunRed(execute=True);
    if plan.reports and len(plan.reports) > 0 {
        redPlan = plan.reports[0];
    }
    fresh = root spawn GetSnapshot();
    if fresh.reports and len(fresh.reports) > 0 {
        snap = fresh.reports[0];
    }
    await reloadIncidents();
    busy = False;
}


impl app.doReset -> None {
    busy = True;
    redPlan = AttackPlan();
    selected = "";
    result = root spawn ResetGrid();
    if result.reports and len(result.reports) > 0 {
        snap = result.reports[0];
    }
    await reloadIncidents();
    busy = False;
}
