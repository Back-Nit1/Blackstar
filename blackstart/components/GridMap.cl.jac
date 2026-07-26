"""The campus as dots and lines. Click anything to cut it.

Islands are colour-coded. A facility the controller switched off is dimmed with
a dashed ring. A facility with no path to any source is red and labelled DARK --
that is a different thing from being shed, and the difference matters.

A cut cable is drawn red and dashed rather than removed, so you can see what
used to be there.
"""

sv import from ..api { NodeView, EdgeView }

glob ISLAND_COLORS: list[str] = [
    "#38bdf8", "#a78bfa", "#fbbf24", "#34d399", "#fb7185", "#c084fc"
];


def:pub island_color(island_id: int) -> str {
    if island_id < 0 {
        return "#ef4444";
    }
    return ISLAND_COLORS[island_id % len(ISLAND_COLORS)];
}


def:pub kind_radius(kind: str) -> float {
    if kind == "utility" { return 21.0; }
    if kind == "substation" { return 18.0; }
    if kind == "tieswitch" { return 13.0; }
    if kind == "generator" or kind == "battery" { return 14.0; }
    if kind == "route" { return 12.0; }
    if kind == "feeder" { return 14.0; }
    return 11.0;
}


def:pub kind_glyph(kind: str) -> str {
    if kind == "utility" { return "GRID"; }
    if kind == "substation" { return "SUB"; }
    if kind == "tieswitch" { return "TIE"; }
    if kind == "generator" { return "GEN"; }
    if kind == "battery" { return "UPS"; }
    if kind == "route" { return "RD"; }
    if kind == "feeder" { return "FDR"; }
    return "";
}


def:pub NodeDot(
    dot: NodeView, isSelected: bool, onSelect: Callable[[str], None]
) -> JsxElement {
    def handle(e: MouseEvent) {
        onSelect(dot.label);
    }

    color = island_color(dot.island_id);
    dead = not dot.alive;
    isDark = dot.tier > 0 and dot.island_id < 0;
    fill = "#111c33" if (dead or dot.shed or isDark) else color;
    stroke = "#ef4444" if (dead or isDark) else color;
    r = kind_radius(dot.kind);
    glyph = kind_glyph(dot.kind);

    return <g className="dot" onClick={handle} opacity={"0.5" if dot.shed else "1"}>
        {if isSelected {
            <circle cx={str(dot.x)} cy={str(dot.y)} r={str(r + 7.0)}
                    fill="none" stroke="#e2e8f0" strokeWidth="2"/>
        }}
        <circle
            cx={str(dot.x)} cy={str(dot.y)} r={str(r)}
            fill={fill} stroke={stroke} strokeWidth={"3" if (dead or isDark) else "2"}
            strokeDasharray={"4 3" if dot.shed else "0"}
        />
        {if dot.tier > 0 {
            <text x={str(dot.x)} y={str(dot.y + 4.0)} textAnchor="middle"
                  fontSize="11" fontWeight="700"
                  fill={"#0f172a" if not (dot.shed or isDark) else "#94a3b8"}>
                {str(dot.tier)}
            </text>
        }}
        {if glyph != "" {
            <text x={str(dot.x)} y={str(dot.y + 4.0)} textAnchor="middle"
                  fontSize="9" fontWeight="700"
                  fill={"#0f172a" if not dead else "#f87171"}>
                {glyph}
            </text>
        }}
        <text x={str(dot.x)} y={str(dot.y + r + 13.0)} textAnchor="middle"
              fontSize="10" fill="#cbd5e1">
            {dot.label}
        </text>
        <text x={str(dot.x)} y={str(dot.y + r + 24.0)} textAnchor="middle"
              fontSize="9" fill={"#f87171" if isDark else "#64748b"}>
            {"DARK" if isDark else ("SHED" if dot.shed else dot.detail)}
        </text>
    </g>;
}


def:pub GridMap(
    nodes: list[NodeView],
    edges: list[EdgeView],
    selected: str,
    onSelect: Callable[[str], None]
) -> JsxElement {
    pos: dict[str, NodeView] = {n.id: n for n in nodes};

    return <svg className="map" viewBox="0 0 1000 720" role="img">
        {for (i, e) in enumerate(edges) {
            <line
                key={"e" + str(i)}
                x1={str(pos[e.src].x)} y1={str(pos[e.src].y)}
                x2={str(pos[e.dst].x)} y2={str(pos[e.dst].y)}
                stroke={island_color(pos[e.dst].island_id) if e.live else "#ef4444"}
                strokeWidth={"2.5" if e.live else "2"}
                strokeDasharray={"0" if e.live else "7 5"}
                opacity={"0.7" if e.live else "0.9"}
            />
        }}
        {for n in nodes {
            <NodeDot key={n.id} dot={n} isSelected={n.label == selected}
                     onSelect={onSelect}/>
        }}
    </svg>;
}
