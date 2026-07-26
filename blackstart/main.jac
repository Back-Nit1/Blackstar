"""BLACKSTART - entry point.

Server modules are imported plainly (server is the default context in a `.jac`
file); the `cl { }` block below is the browser half of the same program. One
language, one file tree, one type checker across the wire.

Run it:   jac script web      ->  http://localhost:8000
"""

import from api {
    GridView, NodeView, EdgeView, IslandView, EvidenceView, RedRoundView,
    GetGrid, Tick, CutAsset, RestoreAsset, AskWhy, RunRedRound, ResetGrid
}

cl {
    import ".styles.global.css";
    import from .frontend { app as OperatorConsole }

    def:pub app -> JsxElement {
        return <OperatorConsole/>;
    }
}
