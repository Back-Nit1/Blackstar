"""Handler bodies for the operator screen.

Same shape every time: spawn a walker, take the fresh GridView out of
reports[0], assign it. Write-then-refetch is explicit because a writer call
invalidates the client's read cache.
"""

impl app.doTick -> None {
    busy = True;
    result = root spawn Tick(steps=1);
    if result.reports and len(result.reports) > 0 {
        grid = result.reports[0];
    }
    busy = False;
}


impl app.doToggle -> None {
    if selected == "" {
        return;
    }
    alive = True;
    current = grid;
    if current is not None {
        for n in current.nodes {
            if n.label == selected {
                alive = n.alive;
            }
        }
    }
    busy = True;
    # A flood, this mouse click and RED all land on these same two walkers.
    if alive {
        cut = root spawn CutAsset(label=selected);
        if cut.reports and len(cut.reports) > 0 {
            grid = cut.reports[0];
        }
    } else {
        back = root spawn RestoreAsset(label=selected);
        if back.reports and len(back.reports) > 0 {
            grid = back.reports[0];
        }
    }
    busy = False;
}


impl app.doWhy -> None {
    if selected == "" {
        return;
    }
    busy = True;
    result = root spawn AskWhy(subject=selected);
    if result.reports and len(result.reports) > 0 {
        why = result.reports[0];
        whySubject = selected;
    }
    busy = False;
}


impl app.doRed -> None {
    busy = True;
    result = root spawn RunRedRound(memory_on=memoryOn);
    if result.reports and len(result.reports) > 0 {
        grid = result.reports[0];
    }
    busy = False;
}


impl app.doReset -> None {
    busy = True;
    why = [];
    whySubject = "";
    selected = "";
    result = root spawn ResetGrid();
    if result.reports and len(result.reports) > 0 {
        grid = result.reports[0];
    }
    busy = False;
}
