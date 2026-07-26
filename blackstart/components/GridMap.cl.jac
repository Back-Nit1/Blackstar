"""The grid, as dots and lines. Click any asset to kill or restore it.

Islands are colour-coded, shed buildings are dimmed with a dashed ring, and
anything with no path to a source is red. A cut line is drawn dashed and red
rather than removed, so you can see what used to be there.
"""

sv import from ..api { NodeView, EdgeView }

# One colour per island. Index -1 (no island at all) is always red.
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
    if kind == "gridtie" { return 20.0; }
    if kind == "feeder" { return 15.0; }
    if kind == "solar" or kind == "battery" or kind == "genset" { return 13.0; }
    return 11.0;
}


def:pub kind_glyph(kind: str) -> str {
    if kind == "gridtie" { return "GRID"; }
    if kind == "feeder" { return "FDR"; }
    if kind == "solar" { return "PV"; }
    if kind == "battery" { return "BAT"; }
    if kind == "genset" { return "GEN"; }
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
    fill = "#1e293b" if (dead or dot.shed) else color;
    stroke = "#ef4444" if dead else color;
    opacity = 0.45 if dot.shed else 1.0;
    r = kind_radius(dot.kind);
    glyph = kind_glyph(dot.kind);

    return <g className="dot" onClick={handle} opacity={str(opacity)}>
        {if isSelected {
            <circle cx={str(dot.x)} cy={str(dot.y)} r={str(r + 7.0)}
                    fill="none" stroke="#e2e8f0" strokeWidth="2"/>
        }}
        <circle
            cx={str(dot.x)} cy={str(dot.y)} r={str(r)}
            fill={fill} stroke={stroke} strokeWidth={"3" if dead else "2"}
            strokeDasharray={"4 3" if dot.shed else "0"}
        />
        {if dot.tier > 0 {
            <text x={str(dot.x)} y={str(dot.y + 4.0)} textAnchor="middle"
                  fontSize="11" fontWeight="700"
                  fill={"#f8fafc" if not (dead or dot.shed) else "#94a3b8"}>
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
              fontSize="9" fill="#64748b">
            {"DARK" if dot.island_id < 0 and dot.tier > 0 else dot.detail}
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

    return <svg className="map" viewBox="0 0 1000 640" role="img">
        {for (i, e) in enumerate(edges) {
            <line
                key={"e" + str(i)}
                x1={str(pos[e.src].x)} y1={str(pos[e.src].y)}
                x2={str(pos[e.dst].x)} y2={str(pos[e.dst].y)}
                stroke={island_color(pos[e.dst].island_id) if e.live else "#ef4444"}
                strokeWidth={"2.5" if e.live else "2"}
                strokeDasharray={"0" if e.live else "7 5"}
                opacity={"0.75" if e.live else "0.9"}
            />
        }}
        {for n in nodes {
            <NodeDot key={n.id} dot={n} isSelected={n.label == selected}
                     onSelect={onSelect}/>
        }}
    </svg>;
}
