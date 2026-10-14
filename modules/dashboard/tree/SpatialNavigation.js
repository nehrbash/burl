function next(nodes, currentId, dx, dy) {
    if (!nodes.length) return "";
    const current = nodes.find(node => node.id === currentId);
    if (!current) return nodes[0].id;
    let best = current.id;
    let bestScore = Infinity;
    for (const node of nodes) {
        const x = node.x - current.x, y = node.y - current.y;
        const forward = x * dx + y * dy;
        if (forward <= 1) continue;
        const sideways = Math.abs(x * dy - y * dx);
        const score = Math.hypot(x, y) * (1 + 2 * Math.pow(sideways / forward, 2));
        if (score < bestScore) {
            best = node.id;
            bestScore = score;
        }
    }
    return best;
}
