"""BLACKSTART - entry point.

Server modules are imported plainly (server is the default context in a
`.jac` file); the `cl { }` block below is the browser half of the same
program. One language, one file tree, one type checker across the wire.

Run it:   jac start --dev main.jac
"""

import from api {
    Snapshot, NodeView, EdgeView, IncidentView,
    GetSnapshot, Tick, KillAsset, RestoreAsset, GetIncidents, RunRed, ResetGrid
}

cl {
    import ".styles.global.css";
    import from .frontend { app as OperatorConsole }

    def:pub app -> JsxElement {
        return <OperatorConsole/>;
    }
}
